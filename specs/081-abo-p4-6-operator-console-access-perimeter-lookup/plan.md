# Implementation Plan: Operator console: Access perimeter, lookup, views and class-H ABO actions

**Branch**: `ai/081-abo-p4-6-operator-console-access-perimeter-lookup` | **Date**: 2026-10-07 | **Spec**: `specs/081-abo-p4-6-operator-console-access-perimeter-lookup/spec.md`

**Input**: Feature specification from `specs/081-abo-p4-6-operator-console-access-perimeter-lookup/spec.md`

## Summary

The ops console on the ops host validates the Access JWT, looks up one clinic, and retries parked grant work or cancels an open checkout. Depends on P4.5 and P3.6. Phase P4, size M. Wiring exception: codebase `abo` plus thin wiring in `ai-platform` that adds and freezes class-H `recordOperatorAction` on `VendorEntrypoint` before the ABO calls it. Spikes are none, so this phase does not write `research.md`.

## Technical Context

**Language/Version**: TypeScript on the existing `abo/` Cloudflare Worker and the existing `ai-platform` `VendorEntrypoint` (wrangler, workers types, vitest workers pool already in `abo/package.json`).

**Primary Dependencies**: Consumed `vendor-contracts` `verifyAccessJwt`, `subscriptionRef`, `humanRef`, `canonicalize`, `sha256Hex`, and `CHANNEL_VERSIONS`. No new library. The ABO worker does not grow a second Access checker. `inspectCoverage` stays the frozen P3.6 method.

**Storage**: ABO D1 (`DB`). This unit adds append-only `operator_action`. It reads the existing `checkout`, `checkout_event`, `checkout_status`, `payment`, `reversal`, `grant_request`, `grant_outcome`, `work`, `finding`, `alert`, and `billing_contact` tables. Platform D1 already has `control_audit` (`actor`, `operator_id`, `assertion_sha256` from `ai-platform/migrations/20261003120000_operator_credential_and_platform_alert.sql`). This unit inserts one row there and adds no platform migration. It does not write PostgreSQL. It does not create `payout_import`.

**Testing**: H-XW for E2E-P4.6-01 through E2E-P4.6-07. Titles are prefixed with the E2E id. Tests are red before `abo/src/ops/index.ts` and `recordOperatorAction` exist. The ABO clock is the existing clock module, so expiry follows `setClock`. A local scenario spends at most 2 seconds of real time. `TEST_CLOCK` stays off production and staging wrangler envs.

**Target Platform**: Ops hostname `SELF.fetch` for `/ops/*` via existing `opsFetch` (`OPS_ORIGIN` in `abo/test/system/harness.ts`). `VendorEntrypoint.inspectCoverage`, `listGrants`, `listIssuerKeys`, `listServiceKeys`, `listOperatorCredentials`, and `recordOperatorAction` over the existing `PLATFORM` binding (`entrypoint = "VendorEntrypoint"`). H-XW builds the platform worker from source.

**Project Type**: `abo` plus the named wiring exception: one new method on the existing `VendorEntrypoint`. No second worker and no stub.

**Performance Goals**: One operator and a few orders a day (02 §7 I). Lookup resolves one clinic. Global views are reads of that operator session. No new cap and no new cron.

**Constraints**: `Abo-Contract-Version` is checked before authentication and before any write. A missing or stale console version is HTTP 400 `contract_version_unsupported` and the console reload state. Access validation covers issuer, `aud`, and expiry (K-8 session length is 1 hour). Retry and cancel commit `operator_action`, then call `recordOperatorAction`. Cancel's only platform call is that method. The `inspectCoverage` relay adds no platform write. `paid_late` after a later payment stays the existing sweep. No spike and no new wrangler binding.

**Scale/Scope**: Ops console lookup, clinic page, global views, retry parked grant work, and cancel an open checkout. Passkey ceremony and HP actions stay with P4.7–P4.9. Findings content stays with P4.10.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked against `.specify/memory/constitution.md` (Version 1.0.0) and 02 §7. 02 §7 records that this design complies. No box is unchecked.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable

02 §7 I: one ABO Worker with D1, plus one method on the existing platform Worker. No queue and no Kubernetes. 02 §7 II: the ABO still holds no clinic database credential. It calls the platform only through the existing `PLATFORM` binding. 02 §7 III: vendor-side integrity is the D1 append-only trigger on `operator_action` and the existing `control_audit` insert. This unit does not write PostgreSQL. 02 §7 IV: the ops host rejects a missing, expired, wrong-`aud`, or bad-issuer Access JWT before a page is served. Retry and cancel record the Access email on `operator_action` and on `control_audit`. 02 §7 V: a stale console tab is refused and asked to reload, and nothing is written. A cancelled checkout still accepts a later payment as `paid_late`. Lapsing AI is unchanged.

## Project Structure

### Documentation (this feature)

```text
specs/081-abo-p4-6-operator-console-access-perimeter-lookup/
├── plan.md
├── data-model.md
├── quickstart.md              # implement writes this after the harness is green
├── contracts/
│   └── record-operator-action.md
└── tasks.md                   # not created in this phase
```

`quickstart.md` sections, written after verification:

- What was implemented, and the files added or modified
- The harness command for this unit’s tests only, from `abo/`: `node scripts/build-platform-for-hxw.mjs && npx vitest run --config vitest.cross-worker.config.ts test/system/ops.cross-worker.test.ts`
- Entry point → module chain per E2E id
- No earlier-unit files, combined counts, or full-suite commands
- No manual steps; the harness observes every scenario

### Source Code (repository root)

```text
abo/
├── migrations/0006_operator_action.sql
├── src/
│   ├── worker.ts
│   └── ops/index.ts
├── test/system/
│   ├── hxw-access-fixture.ts
│   └── ops.cross-worker.test.ts
└── vitest.cross-worker.config.ts

ai-platform/src/vendor/entrypoint.ts
```

**Structure Decision**: Console pages, lookup, retry, and cancel are one module, `abo/src/ops/index.ts`. `worker.ts` `fetch` keeps the ops-host `/ops/*` branch and calls that module after the console version gate. `opsFetch` stays in `abo/test/system/harness.ts` and is not rewritten. The wiring exception adds `recordOperatorAction` on the existing `VendorEntrypoint` only. `inspectCoverage`, `listGrants`, and the key and credential list methods stay as they are.

## Consumes Binding

| Consumes | Existing module |
| --- | --- |
| P4.5: none. The unit row freezes nothing | No frozen P4.5 contract. E2E-P4.6-05’s later payment stays `abo/src/work/runner.ts` (`classificationForPayment` treats `cancelled` like `expired`, then `paid_late`) and `abo/src/work/sweep.ts`. This unit calls `runScheduled`. It does not modify those files. |
| P3.6 complimentary and adjustment grant semantics; ceiling policy; `suspend` / `resume` / `inspectCoverage` | `ai-platform/src/vendor/entrypoint.ts` `inspectCoverage`, `suspend`, and `resume`. This unit calls `inspectCoverage` only, with `contract_version`, `access_jwt`, and `org_id`. It does not modify that method, `suspend`, `resume`, or the complimentary, adjustment, or ceiling methods. The relay inserts no `control_audit` row. |

`listGrants` (`specs/067-abo-p3-3-plan-versions-paid-grant-coverage-ledger/contracts/list-grants.md`), `listIssuerKeys`, `listServiceKeys`, and `listOperatorCredentials` are existing class-M methods. This unit calls them and does not modify them. `runDueGrantWork` in `abo/src/work/grant.ts` stays the grant runner E2E-P4.6-04 calls after retry. This unit does not modify `grant.ts`.

## Files

| Path | Action | FR |
| --- | --- | --- |
| `abo/migrations/0006_operator_action.sql` | Create | FR-007 |
| `abo/src/ops/index.ts` | Create | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `abo/src/worker.ts` | Modify | FR-001, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `ai-platform/src/vendor/entrypoint.ts` | Modify | FR-001, FR-007 |
| `abo/test/system/hxw-access-fixture.ts` | Modify | FR-007 |
| `abo/vitest.cross-worker.config.ts` | Modify | FR-001 |
| `abo/test/system/ops.cross-worker.test.ts` | Create | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 |
| `specs/081-abo-p4-6-operator-console-access-perimeter-lookup/data-model.md` | Created this phase | FR-007 |
| `specs/081-abo-p4-6-operator-console-access-perimeter-lookup/contracts/record-operator-action.md` | Created this phase | FR-007 |

`quickstart.md` is not written in this phase. `research.md` is not written: Spikes is none.

`wrangler.toml` is unchanged. H-XW already binds `ACCESS_TEAM_DOMAIN` `access.test` and `ACCESS_AUD` `vendor-access-aud` on the ABO worker. `opsFetch` already forwards request headers to `SELF.fetch`.

`worker.ts`: `Env` gains `ACCESS_TEAM_DOMAIN`, `ACCESS_AUD`, and `PLATFORM` methods `inspectCoverage`, `listGrants`, `listIssuerKeys`, `listServiceKeys`, `listOperatorCredentials`, and `recordOperatorAction`. `handleOps` still calls `checkContractVersion(request, "aboConsole")` before the ops module. On failure it returns that gate body with `reload: true` added, status 400, and the existing `Abo-Contract-Version` header. The clinic channel builder in `clinic-api/version.ts` is not changed. On success it calls `handleOps` from `abo/src/ops/index.ts`.

`hxw-access-fixture.ts`: `mintHxwVendorAccessJwt` puts `jti` on the payload (a UUID when the caller omits it) and accepts an optional `iss` override for the bad-issuer case. Default `iss` stays `https://access.test`. `verifyAccessJwt` ignores the extra `jti` claim, so earlier suites that mint with this helper still verify.

`vitest.cross-worker.config.ts` adds `test/system/ops.cross-worker.test.ts` to `test.include`. The unit command still names only that file.

`entrypoint.ts`: add `recordOperatorAction: "H"` to `METHOD_CLASS`. That adds one method row. The P3.1 rows stay. The method is specified in `contracts/record-operator-action.md`. It uses the existing `verifyHpAccess` and `writeEntrypointAudit`. It does not change `inspectCoverage`.

`ops/index.ts` is the only new ABO module. Every route below is reached from the test layout. The Access JWT is the `Cf-Access-Jwt-Assertion` header (02 §3.3 class H). After the version gate, a missing header, a token `verifyAccessJwt` rejects, or a verified payload whose `jti` is not a non-empty string is HTTP 401 `{ code: "unauthenticated", message: "unauthenticated", contract_version }` and writes nothing. `nowSeconds` comes from the ABO clock. Certs are `{ issuer: "https://" + ACCESS_TEAM_DOMAIN, keys }` from `GET https://{ACCESS_TEAM_DOMAIN}/cdn-cgi/access/certs`. The checker is `verifyAccessJwt` with `aud` `ACCESS_AUD`. Success responses use the existing clinic JSON helper: `contract_version` in the body and `Abo-Contract-Version` on the response. Current console version is 1.

| Route | Behaviour |
| --- | --- |
| `GET /ops/lookup?q=` | One clinic. `AIC-…` matches `subscriptionRef(org_id)` over distinct `org_id` values in `billing_contact`, `checkout`, and `coverage_view`. `org_id` matches that id. Billing email matches `billing_contact.email` on the highest `version` for that org. `CK-` matches `checkout.reference`. `PAY-` matches `payment.reference`. `GR-` matches `humanRef("GR", grant_request.grant_id)`. The body is `{ contract_version, org_id }`. |
| `GET /ops/clinics/:orgId` | Clinic page. Calls `PLATFORM.inspectCoverage({ contract_version, access_jwt, org_id })` and shows `detail` JSON `terms`, `grants`, and `reservations`. It does not add a suspension field and does not call `suspend`. It also shows that org’s checkouts with `checkout_event`, payments with `classification` and `disposition`, reversals, grant requests with `grant_outcome` and `receipt`, `operator_action` rows whose `subject` is that `org_id` or a `checkout_id` / `work_id` of that org, `finding` rows for that org, and `alert` rows with `active = 1` whose `alert_key` contains that `org_id` or one of its checkout or payment ids. |
| `GET /ops/parked` | `work` rows with `state = 'parked'`. E2E-P4.6-04 retries from this view. |
| `GET /ops/findings` | Every `finding` row. No resolution table exists yet, so each row is open. |
| `GET /ops/grants` | One `listGrants({ contract_version })` call. The body groups that array by `source_kind` and by `operator_credential_id`. |
| `GET /ops/payout-imports` | `{ contract_version, payout_imports: [] }`. This unit does not create or query `payout_import`. |
| `GET /ops/registries` | `listIssuerKeys`, `listServiceKeys`, and `listOperatorCredentials`, each with `contract_version` only. The body is the three `detail` arrays. |
| `POST /ops/parked/:workId/retry` | The `work` row must be `kind = 'grant'` and `state = 'parked'`. One update sets `state = 'open'`, `lease_until` null, `last_error` null, and `next_attempt_at` null. Then insert `operator_action` (`action` `Retry parked work`, `subject` the `work_id`, `result` `open`, `assertion_sha256` null, `params_sha256` the hex SHA-256 of `canonicalize({ action, subject })`). Then `PLATFORM.recordOperatorAction` with `access_jwt`, and `action`, `subject`, and `action_id` copied from that row. |
| `POST /ops/checkouts/:checkoutId/cancel` | `checkout_status.state` must be `open`. Update it to `cancelled` and set `last_event_at` from the ABO clock. Insert `checkout_event` (`kind` `cancelled`, `source` `operator`, `ref` the `action_id`, `actor` the email). Do not update `checkout` (append-only). Then the same `operator_action` insert (`action` `Cancel an open checkout`, `subject` the `checkout_id`, `result` `cancelled`) and the same `recordOperatorAction` call. That call is this route’s only platform call. |

`actor_email` is the verified `email` claim. `access_jti` is the verified payload `jti`. The `operator_action` insert and its `fact_log` row are one D1 batch, and that batch commits before `recordOperatorAction`.

E2E-P4.6-04 does not apply the grant inside the retry route. The test inserts one parked `grant` work row, retries through `opsFetch`, sees `open`, then calls the existing `runDueGrantWork`. The platform `grant` call succeeds. The grant outcome is `applied`.

E2E-P4.6-05 opens a checkout through the existing clinic checkout API, cancels it through `opsFetch`, then lets the existing minute sweep confirm a later payment. `checkout_status.state` becomes `paid_late`. This unit does not change that sweep.

## Test Layout

| ID | Harness | Title prefix | Entry | Proves |
| --- | --- | --- | --- | --- |
| E2E-P4.6-01 | H-XW | `E2E-P4.6-01` | `opsFetch` → `SELF.fetch` on `OPS_ORIGIN` + `/ops/*` with no `Cf-Access-Jwt-Assertion`, an expired JWT, a wrong `aud`, and a wrong `iss`. Then `platformCall("recordOperatorAction", …)` with no JWT, an expired JWT, and a wrong `aud` | FR-001. Each ops-host request is HTTP 401 `unauthenticated` and inserts no `operator_action`. Issuer is checked by the same `verifyAccessJwt` call. Each entrypoint call is `rejected` / `unauthenticated` and inserts no `control_audit` row |
| E2E-P4.6-02 | H-XW | `E2E-P4.6-02` | `opsFetch` lookup `GET /ops/lookup?q=` with `AIC-…`, then `GET /ops/clinics/:orgId`, then the same session’s `GET /ops/parked`, `/ops/findings`, `/ops/grants`, `/ops/payout-imports`, and `/ops/registries` | FR-002, FR-003, FR-004, FR-008. The clinic page shows `inspectCoverage` terms and the ABO checkouts and payments, plus events, reversals, grant requests and receipts, operator actions, findings, and alerts. Response header `Abo-Contract-Version` is `1` and the body `contract_version` is `1`. `payout_imports` is `[]` |
| E2E-P4.6-03 | H-XW | `E2E-P4.6-03` | `opsFetch` `GET /ops/lookup?q=` by billing email, `PAY-`, `org_id`, `CK-`, and `GR-` | FR-002. Each lookup returns the same `org_id` as the `AIC-…` lookup |
| E2E-P4.6-04 | H-XW | `E2E-P4.6-04` | `opsFetch` `GET /ops/parked`, then `POST /ops/parked/:workId/retry`, then `runDueGrantWork`. `platformCall("recordOperatorAction")` again with the same `action_id` | FR-005, FR-007. The harness inserts one parked `grant` work row. Retry moves it to `open`. After `runDueGrantWork` the grant is `applied`. One `operator_action` row stores `actor_email` and `access_jti`. One `control_audit` row stores that email as `actor` and `operator_id`, `action` `Retry parked work`, `target` the `action_id`, and `assertion_sha256` null. The repeated `action_id` is `ok` and does not insert a second row |
| E2E-P4.6-05 | H-XW | `E2E-P4.6-05` | `opsFetch` `POST /ops/checkouts/:checkoutId/cancel` on an open checkout, then the existing sweep for a later payment. `platformCall("recordOperatorAction")` again with the same `action_id` | FR-006, FR-007. The checkout becomes `cancelled`. The later payment becomes `paid_late`. `operator_action` stores the actor email and `access_jti`. `control_audit` stores the Access email. The repeated `action_id` inserts no second row. The cancel route’s only platform method is `recordOperatorAction` |
| E2E-P4.6-06 | H-XW | `E2E-P4.6-06` | `opsFetch` `POST /ops/checkouts/:checkoutId/cancel` with a stale `Abo-Contract-Version`, and with the header missing | FR-008. Both responses are HTTP 400 `contract_version_unsupported` with `reload: true`, before authentication and before any write. The checkout stays `open`. No `operator_action` row is inserted |
| E2E-P4.6-07 | H-XW | `E2E-P4.6-07` | `opsFetch` `GET /ops/clinics/:orgId` relay to `PLATFORM.inspectCoverage`, then `platformCall("inspectCoverage")` with no `access_jwt` | FR-003. The relay sends the operator JWT as `access_jwt`. The frozen call returns `ok` and `detail` JSON `{ terms, grants, reservations }`. The result does not echo `email`. `control_audit` count is unchanged and no other actor-email row is inserted. A missing Access JWT is `rejected` / `unauthenticated` and still writes nothing. The clinic page shows those terms, grants, and reservations |

All seven tests live in `abo/test/system/ops.cross-worker.test.ts`. Each title starts with the E2E id. Tests are written and run first, and they fail before `abo/src/ops/index.ts` exists and before `recordOperatorAction` exists.

Shared setup uses the existing H-XW helpers (`setupCrossWorkerHarness`, `opsFetch`, `mintVendorAccessJwt`, `platformCall`, `setClock`, `runScheduled`). E2E-P4.6-04 calls `runDueGrantWork` from `abo/src/work/grant.ts`. E2E-P4.6-05 uses the Paymob stub already bound in the H-XW config.

Module chains the quickstart will record:

- E2E-P4.6-01: `opsFetch` → `worker.ts` `handleOps` → `ops/index.ts` `verifyAccessJwt`; `platformCall` → `VendorEntrypoint.recordOperatorAction` → `verifyHpAccess`
- E2E-P4.6-02: `opsFetch` → `ops/index.ts` lookup and clinic page → `PLATFORM.inspectCoverage`; same session → parked, findings, `PLATFORM.listGrants`, payout imports, `PLATFORM.listIssuerKeys` / `listServiceKeys` / `listOperatorCredentials`
- E2E-P4.6-03: `opsFetch` → `ops/index.ts` lookup
- E2E-P4.6-04: `opsFetch` → `GET /ops/parked` → `POST` retry → `operator_action` → `PLATFORM.recordOperatorAction` → `work/grant.ts` `runDueGrantWork`
- E2E-P4.6-05: `opsFetch` → cancel → `operator_action` → `PLATFORM.recordOperatorAction`; later `worker.ts` `scheduled` → `work/sweep.ts` → `work/runner.ts` `paid_late`
- E2E-P4.6-06: `opsFetch` → `worker.ts` version gate (`reload: true`); `ops/index.ts` is not called
- E2E-P4.6-07: `opsFetch` → `ops/index.ts` → `PLATFORM.inspectCoverage`; `platformCall("inspectCoverage")` with no JWT

## Sequencing

1. Add `abo/test/system/ops.cross-worker.test.ts` and the vitest include. Teach `mintHxwVendorAccessJwt` to set `jti`. Run the harness command. The seven tests fail because `abo/src/ops/index.ts` and `recordOperatorAction` are absent.
2. Add `recordOperatorAction` on `VendorEntrypoint` as `contracts/record-operator-action.md` specifies. Add `abo/migrations/0006_operator_action.sql` and `abo/src/ops/index.ts`. Delegate `/ops/*` from `worker.ts` after the version gate, and add `reload: true` on that gate’s console refusal.
3. Re-run the same harness command until E2E-P4.6-01 through E2E-P4.6-07 pass. Earlier suites are not part of this command.

The file list above is the whole change. A tasks breakdown of these files and the seven scenarios stays within the M band and under 40. It is not padded up to the M-band floor.

## Complexity Tracking

02 §7 records no constitution violation for this design. Nothing is entered here.
