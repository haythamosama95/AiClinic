# Implementation Plan: Console passkey ceremony and ABO-side HP actions

**Branch**: `ai/082-abo-p4-7-console-passkey-ceremony-abo-side-hp` | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/082-abo-p4-7-console-passkey-ceremony-abo-side-hp/spec.md`

## Summary

The ABO console verifies its own HP actions with a WebAuthn `get` assertion over the package operation object, checked against one fresh `listOperatorCredentials` response, a five-minute `issued_at`, and a single-use challenge hash in ABO D1. Depends on P4.6 and P3.1, phase P4, size M. The same `abo/src/ops/` module then publishes, retires, and reinstates offer and terms versions, releases a withheld payment into the existing grant path, records a manual chargeback into the P4.5 effect pipeline, and erases one tenant's contact fields and raw provider bodies.

## Technical Context

**Language/Version**: TypeScript on the existing ABO Cloudflare Worker (`abo/`).

**Primary Dependencies**: `vendor-contracts` (`validateOperation`, `operationChallenge`, `verifyAssertion`, `canonicalize`, `sha256Hex`, and the testkit `createSoftwareAuthenticator`). Existing `PLATFORM` binding methods `listOperatorCredentials` and `recordOperatorAction`. Existing ABO clock (`clockNowMs` / `clockNowIso`).

**Storage**: ABO D1 and R2. New tables `assertion_used` and `payment_release`. Existing `offer_event`, `offer_version`, `terms_version`, `operator_action`, `billing_contact`, `reversal`, and `work`. Terms text and raw provider bodies in R2.

**Testing**: Harness H-XW. One vitest file, titles prefixed with the E2E id. Red tests before implementation.

**Target Platform**: ABO ops host (`OPS_HOST`), `/ops/*`, delegated by the existing worker fetch. Catalogue and checkout outcomes are read on the billing host through the existing `billingFetch`.

**Project Type**: ABO worker module extension. Codebase is `abo`. No second codebase.

**Performance Goals**: One operator and a few orders a day (02 §7). Each HP verification calls `listOperatorCredentials` once.

**Constraints**: `rpId` is `OPS_HOST`. `clientDataJSON.origin` is `https://` plus `OPS_HOST`. `type` is `webauthn.get`. User presence and user verification are both set. Algorithm is ES256 or EdDSA. `issued_at` must be within 5 minutes of the ABO clock. The challenge is base64url(SHA-256(canonical operation object)). The challenge hash stored for single use is the hex SHA-256 of that canonical operation. An assertion `credential_id` absent from the active-only list is `rejected` with `credential_not_active` (pending, revoked, and unknown ids). `credential_revoked` remains the platform credential-read code when that read sees `status` `revoked` (04 §1.5). This unit does not add a platform method. `offer_event` and `payment_release` are append-only. `offer_version` and `terms_version` stay append-only. A fully reversed release writes no `payment_release` and starts no grant. The spec names no refusal code for that release or for an assertion whose operation does not match the challenge; those calls are refused and `operator_action` records the result.

**Scale/Scope**: Seven H-XW scenarios. Actions live in `abo/src/ops/`. Reinstate is the same catalogue action as publish and retire and has no E2E id.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked again against 02 §7 and constitution v2.0.0. 02 §7 records no violation for this unit.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
      — One operator publishes or retires what a clinic can buy, releases a withheld payment, records a manual chargeback, and erases one tenant's payer contact (02 §7 principle I; spec §4.1 Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
      — The work stays in the existing ABO worker, D1, and R2 (02 §7 principle I).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
      — Codebase is `abo`. The platform is called only through the frozen `PLATFORM` binding. No clinical data and no database credential (02 §7 principle II).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
      — Clinic-side state is unchanged. Vendor-side integrity uses the existing D1 append-only triggers, and the new `payment_release` and `assertion_used` tables use the same abort-update and abort-delete triggers (02 §7 principle III).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
      — HP actions require the existing Access JWT plus a WebAuthn assertion. Accepted actions write `operator_action` and then `recordOperatorAction`. Contact erasure blanks fields and keeps the row and the hashes (02 §7 principle IV; 03 §2.3).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable
      — This unit does not add an AI write path. Value-moving operator actions require the passkey. Lapsing AI is outside this unit (02 §7 principle V).

## Project Structure

### Documentation (this feature)

```text
specs/082-abo-p4-7-console-passkey-ceremony-abo-side-hp/
├── plan.md
├── data-model.md
└── quickstart.md          # implement writes this after the seven H-XW tests pass
```

`research.md` is omitted. Spikes are none. `contracts/` is omitted. Freezes has no wire shape. `tasks.md` is not created in this phase.

#### Quickstart outline

Implement writes `quickstart.md` after the harness is green. Sections only:

- What was implemented, and the files added or modified
- Harness command for this unit's tests only: `node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/hp-actions.cross-worker.test.ts` from `abo/`
- Entry point → module chain per E2E id (the Test Layout chains below)
- Manual steps: none. The harness can see every behaviour in the test plan

### Source Code (repository root)

```text
abo/migrations/0007_hp_actions.sql
abo/src/ops/index.ts
abo/src/clinic-api/checkouts.ts
abo/src/work/grant.ts
abo/test/system/hp-actions.cross-worker.test.ts
abo/vitest.cross-worker.config.ts
```

**Structure Decision**: Codebase is `abo`. `handleOps` in `abo/src/ops/index.ts` gains the HP actions. The worker fetch already delegates `OPS_HOST` + `/ops/*` and already exposes `listOperatorCredentials` and `recordOperatorAction` on `PLATFORM`. `opsFetch` stays in `abo/test/system/harness.ts`. The shared package builds the operation object and the challenge; this unit does not change the package. `VendorEntrypoint` stays unchanged.

## Consumes Binding

| Consumes | Bound to | This unit |
| --- | --- | --- |
| P4.6 class-H `recordOperatorAction` on `VendorEntrypoint` | `ai-platform/src/vendor/entrypoint.ts` `recordOperatorAction` (class H). ABO call site `recordPlatformOperatorAction` in `abo/src/ops/index.ts`, via `env.PLATFORM.recordOperatorAction`, arguments `contract_version`, `access_jwt`, `action`, `subject`, `action_id`. One `control_audit` insert; every other platform table unchanged; `assertion_sha256` null on that audit row. | Called after a successful HP action commits `operator_action`. Not called on refusal. Not modified. |
| P3.1 method dispatch, class table, auth refusal codes, credential lifecycle, alert body format, `platform_alert` | `ai-platform/src/vendor/entrypoint.ts` `listOperatorCredentials` (class M). Returns `ok`, `detail` the JSON text of active `{credential_id, public_key_cose, alg}` rows, empty `code`, no `receipt`. Credential promote, revoke, and `credential_revoked` stay on that entrypoint. Access refusal `unauthenticated` is already applied by `verifyOpsAccess` in `abo/src/ops/index.ts`. | Each HP verification calls `listOperatorCredentials` once and looks up `credential_id` in that array. Not modified. |

## Files

| Path | Change | FR |
| --- | --- | --- |
| `abo/migrations/0007_hp_actions.sql` | Create `assertion_used` (`challenge_sha256` primary key) and `payment_release` (`payment_id` primary key, `operator_action_id`, `at`). Both abort update and delete. | FR-002, FR-008 |
| `abo/src/ops/index.ts` | HP verification and the actions below. Routes: `POST /ops/offers/:offerId/publish`, `POST /ops/offers/:offerId/retire`, `POST /ops/offers/:offerId/reinstate`, `POST /ops/payments/:paymentId/release`, `POST /ops/payments/:paymentId/chargeback`, `POST /ops/orgs/:orgId/erase-contact`. `operator_action.action` and the operation `op` are `publish_offer`, `retire_offer`, `reinstate_offer`, `release_payment`, `manual_chargeback`, or `erase_contact`. `subject` is the offer id, payment id, or org id in the path. `recordOperatorAction` copies `action`, `subject`, and `action_id` from that row. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/src/clinic-api/checkouts.ts` | `sellableOfferVersion` returns null when the latest `offer_event` for the offer is not `published`. When the latest event is `published`, it returns the latest published version. Checkout then keeps returning `offer_unavailable`. | FR-006 |
| `abo/src/work/grant.ts` | The existing grant work path (`runDueGrantWork` / the payment's `grant:${paymentId}` row) also runs when a `payment_release` row exists for that payment. Disposition `grant` stays the paid path's gate. A withheld payment is not updated. | FR-008 |
| `abo/test/system/hp-actions.cross-worker.test.ts` | H-XW tests E2E-P4.7-01 through E2E-P4.7-07. The harness builds the operation and challenge with the package and signs with `createSoftwareAuthenticator` using a credential `listOperatorCredentials` lists as active. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/vitest.cross-worker.config.ts` | Add the new test file to the H-XW `include` list. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |

### HP verification

Every new route runs the existing `verifyOpsAccess` first. A missing, expired, or wrong-`aud` Access JWT is `unauthenticated` and writes nothing.

The request carries `operation` and `assertion`. The operation is `{op, params, actor_email, issued_at, nonce, contract_version}`. `params` is the action input without the assertion. `validateOperation` and `operationChallenge` come from the package. `actor_email` must equal the Access JWT email (`actor_email_mismatch`). `issued_at` more than 5 minutes from `clockNowMs` is `assertion_expired`. A class HP call that omits `assertion` is `assertion_required`. These refusals insert `operator_action` and do not call `recordOperatorAction`. Bootstrap `registerOperatorCredential` is not an ABO route.

The challenge hash is `sha256Hex(canonicalize(operation))`. If `assertion_used` already holds it, the call is `assertion_used` and the HP write does not run. On acceptance the hash is inserted before the HP write.

The check calls `listOperatorCredentials` once per verification. It looks up the assertion's `credential_id` in that active-only array. An absent id is `credential_not_active`. `verifyAssertion` uses the matching `public_key_cose` and `alg`, `rpId` `OPS_HOST`, and origin `https://` plus `OPS_HOST`. An assertion over a different operation fails that check, is refused, and `operator_action` records the result. The spec names no separate code for that mismatch.

### Catalogue action

Publish, retire, and reinstate share one handler. `op` is `publish_offer`, `retire_offer`, or `reinstate_offer`. Publish inserts `offer_version` at the new price with `assertion_sha256` set to the challenge hash, inserts `offer_event` kind `published`, and stores the terms text at the new `terms_version.text_r2_key`. Retire inserts `offer_event` kind `retired`. Reinstate inserts `offer_event` kind `reinstated`. Past `offer_version` rows stay. An open checkout keeps its snapshot and is charged and granted by the existing paid path. `listOffers` already hides an offer whose latest event is not `published`. After `operator_action` commits, the handler calls `recordOperatorAction`.

### Release

`op` is `release_payment`. The payment is withheld. If existing reversal rows already treat it as fully reversed (`is_full`), the call is refused, `operator_action` records the result, and there is no `payment_release` and no grant work. Otherwise the handler appends `payment_release` and inserts the same `work` row the paid path inserts (`kind` `grant`, dedupe `grant:${paymentId}`). The harness runs `runDueGrantWork` until the grant is applied.

### Manual chargeback

`op` is `manual_chargeback`. The handler inserts `reversal` with `source` `operator`, `detected_via` `manual`, `kind` `chargeback`, amount and cumulative equal to the payment amount, `is_full` true, `recorded_by` the Access email, and `evidence_sha256` the challenge hash. The dedupe key and reversal id use the existing `reversalDedupeKey` and `reversalIdFromDedupeKey` with that payment's parent transaction. `effect` comes from `determineReversalEffect`. The handler raises AL-06 through `raiseAlert`, then `insertReverseWorkRow` and `processReverseWork` so the existing pipeline voids on the real platform worker, reverses the current term, and holds queued. `operator_action` is committed before `recordOperatorAction`.

### Erasure

`op` is `erase_contact`. The handler blanks `name`, `email`, and `phone` on every `billing_contact` version of that `org_id`, sets `erased_at` and `erased_by`, deletes that tenant's raw R2 bodies, and leaves the hash columns and `ledger/` objects. The existing checkout path returns `billing_contact_required` when the latest contact has `erased_at` set. `operator_action` is committed before `recordOperatorAction`.

## Test Layout

Tests are written first and observed failing. Each title is prefixed with its E2E id. Harness H-XW (`abo/test/system/`, cross-worker vitest, real platform worker from source). Entry is `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*`.

| ID | Title prefix | Entry → module chain | Assertion |
| --- | --- | --- | --- |
| E2E-P4.7-01 | `E2E-P4.7-01` | `opsFetch` publish → `handleOps` catalogue action → `offer_event` / `offer_version` / terms R2 / `operator_action` / `recordOperatorAction`. Outcome: `billingFetch` `GET /v1/offers` (`listOffers`) and the open v1 checkout's existing charge and grant. | Publish offer v2 at a new price → `/v1/offers` shows v2; the open v1 checkout is still charged and granted at v1. |
| E2E-P4.7-02 | `E2E-P4.7-02` | `opsFetch` retire → `handleOps` catalogue action. Outcome: `billingFetch` `GET /v1/offers` and `POST /v1/checkouts` (`sellableOfferVersion`), and existing platform terms on the real platform worker. | Offer gone from `/v1/offers`; checkout returns `offer_unavailable`; platform terms unchanged. |
| E2E-P4.7-03 | `E2E-P4.7-03` | `opsFetch` three HP calls → `handleOps` verification → `operator_action`. The test clock places one `issued_at` more than 5 minutes in the past. One call omits `assertion`. One call's operation does not match the challenge. | Refused. `assertion_required` and `assertion_expired` use those codes. The mismatch is refused. `operator_action` records each result. |
| E2E-P4.7-04 | `E2E-P4.7-04` | `opsFetch` release → `handleOps` → `payment_release` and grant `work` → `runDueGrantWork`. The refusal case uses a withheld payment whose reversal rows are already fully reversed. | Withheld release → grant applied. Fully reversed release → refused, no `payment_release`, no grant. |
| E2E-P4.7-05 | `E2E-P4.7-05` | The test completes a real H-XW purchase so the payment funds the current term. `opsFetch` chargeback → `handleOps` → `reversal` → `determineReversalEffect`, `raiseAlert`, `insertReverseWorkRow`, `processReverseWork` → platform `voidForReversal`. | `source=operator`, `detected_via=manual`. Effect void, term reversed, queued held, AL-06. |
| E2E-P4.7-06 | `E2E-P4.7-06` | `opsFetch` erase → `handleOps` → `billing_contact` and R2 evidence keys. Outcome: D1 hashes, `ledger/` export, then `billingFetch` `POST /v1/checkouts`. | Contact fields blank on every version; `erased_at` set; raw R2 bodies deleted; hashes and ledger export intact; next checkout `billing_contact_required`. |
| E2E-P4.7-07 | `E2E-P4.7-07` | Platform `revokeOperatorCredential` on the real `VendorEntrypoint`, then `opsFetch` HP → `handleOps` calls `listOperatorCredentials` again. | The next HP action is refused with `credential_not_active`. |

## Sequencing

1. Add the H-XW test file and its vitest include. Run it and observe E2E-P4.7-01 through E2E-P4.7-07 failing.
2. Add `0007_hp_actions.sql`.
3. Implement HP verification in `abo/src/ops/index.ts` so E2E-P4.7-03 and E2E-P4.7-07 pass.
4. Implement the catalogue action and the checkout sellable check so E2E-P4.7-01 and E2E-P4.7-02 pass.
5. Implement release and the grant-work eligibility so E2E-P4.7-04 passes.
6. Implement manual chargeback through the existing reversal pipeline so E2E-P4.7-05 passes.
7. Implement erasure so E2E-P4.7-06 passes.
8. After all seven tests pass, implement writes `quickstart.md`. That file is not part of this phase.

## Complexity Tracking

02 §7 records no constitution violation for this unit. No row.
