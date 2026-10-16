# Implementation Plan: Console relays: platform configuration, registries and bootstrap

**Branch**: `ai/084-abo-p4-9-console-relays-configuration-registries-bootstrap` | **Date**: 2026-10-07 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/084-abo-p4-9-console-relays-configuration-registries-bootstrap/spec.md`

## Summary

The operator console relays plan-version publish and retire, ceiling policy, issuer-key register, retire, and revoke, service-key register and revoke, operator-credential bootstrap, registration, and revocation, kill switches, routing policy, cohort, capability lifecycle, token contract, and support lookup. Depends on P4.7 and P3.10, phase P4, size M. Each relay is an `/ops/*` route on the existing ABO worker and calls the existing `VendorEntrypoint` method over the `PLATFORM` binding. The platform verifies the call. This unit does not add a worker, a hostname, or a route family.

## Technical Context

**Language/Version**: TypeScript on the existing ABO Cloudflare Worker (`abo/`).

**Primary Dependencies**: `vendor-contracts` testkit (`createSoftwareAuthenticator` for the WebAuthn `create` attestation and the approving assertion; `createAboGrantSigner` for the next ABO service key; `createIssuer` for the drill issuer `kid`). Existing `PLATFORM` methods on the real platform worker: `registerOperatorCredential`, `revokeOperatorCredential`, `registerIssuerKey`, `retireIssuerKey`, `revokeIssuerKey`, `registerServiceKey`, `revokeServiceKey`, `publishPlanVersion`, `retirePlanVersion`, `setCeilingPolicy`, `publishRoutingPolicy`, `canaryRoutingPolicy`, `promoteRoutingPolicy`, `rollbackRoutingPolicy`, `armKillSwitch`, `activateCohort`, `promoteCohort`, `deprecateCapability`, `retireCapability`, `beginTokenContractRotation`, `retireTokenContract`, `supportLookup`, and the existing paid `grant`. Existing `opsFetch`, `verifyOpsAccess`, and `insertRelayOperatorAction`. Existing clock (`setClock` in the H-XW harness).

**Storage**: Existing ABO D1 table `operator_action`. Existing platform D1 tables written by the methods above. No new table and no new entity.

**Testing**: Harness H-XW. One vitest file, titles prefixed with the E2E id. Red tests before implementation.

**Target Platform**: ABO ops host (`OPS_HOST`), `/ops/*`, delegated by the existing worker fetch. AI-token, routing, and kill-switch outcomes are `POST /v1/requests` on the real platform worker (`PLATFORM_HTTP`). The paid grant is the existing grant path. The ABO secret switch is the existing `ABO_GRANT_KEY` value passed into that worker's `fetch` and `scheduled` handlers.

**Project Type**: ABO worker module extension. Codebase is `abo`. No second codebase.

**Performance Goals**: One operator (02 §7). A revoked issuer `kid` is rejected within one config-cache TTL (≤ 30 s). The H-XW platform binding `CONFIG_CACHE_TTL_MS` is `100`. Credential activation and that TTL advance use the platform test clock. No real sleep.

**Constraints**: The console forwards the Access JWT. Each HP method also forwards `assertion`, except bootstrap `registerOperatorCredential` while `operator_credential` is empty. The platform verifies. These relays do not call `recordOperatorAction`. One `operator_action` per action, Access email as actor. No new refusal code: platform refusals stay the codes in the cited 04 §1.3 rows. No test-only secret setter. `ai-platform/scripts/bootstrap-routing-policy.sh` stays until P7.1. `/control/*` stays until P3.10. Platform methods are not modified.

**Scale/Scope**: Seven H-XW scenarios. Relays live in `abo/src/ops/`. `handleOps` in `abo/src/worker.ts` already keeps the `/ops/*` prefix.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

Checked again against 02 §7 and constitution v2.0.0. 02 §7 records no violation for this unit.

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
      — One operator publishes the plan a clinic can be granted, sets the ceiling, registers the keys and credentials that admit that clinic, and can stop a capability or look up one request (02 §7 principle I; spec §4.1 Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
      — The work stays in the existing ABO worker. Relays are request handlers on `/ops/*`. No second worker, hostname, or route family (02 §7 principle I).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
      — Codebase is `abo`. The platform is called only through the existing `PLATFORM` binding. No clinical data and no database credential (02 §7 principle II).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
      — Clinic-side state is unchanged. Vendor-side integrity stays on the existing platform methods and the existing ABO `operator_action` write (02 §7 principle III).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
      — `verifyOpsAccess` requires the Access JWT. HP relays forward `assertion`, except bootstrap while the credential table is empty. The platform writes `control_audit` on the methods that already do. One `operator_action` is written per action with the Access email as actor (02 §7 principle IV).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable
      — Registry and plan relays are class HP and the platform checks the passkey. Kill switch, routing, cohort, capability lifecycle, token contract, and support lookup are class H. This unit does not add an AI write path into clinic data (02 §7 principle V).

## Project Structure

### Documentation (this feature)

```text
specs/084-abo-p4-9-console-relays-configuration-registries-bootstrap/
├── plan.md
└── quickstart.md          # implement writes this after the seven H-XW tests pass
```

`research.md` is omitted. Spikes are none. `data-model.md` is omitted. This unit defines no entities. `contracts/` is omitted. Freezes has no wire shape. `tasks.md` is not created in this phase.

#### Quickstart outline

Implement writes `quickstart.md` after the harness is green. Sections only:

- What was implemented, and the files added or modified
- Harness command for this unit's tests only: `node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/configuration-relays.cross-worker.test.ts` from `abo/`
- Entry point → module chain per E2E id (the Test Layout chains below)
- Manual steps: none. The harness can see every behaviour in the test plan

### Source Code (repository root)

```text
abo/src/ops/index.ts
abo/test/system/configuration-relays.cross-worker.test.ts
abo/vitest.cross-worker.config.ts
```

**Structure Decision**: Codebase is `abo`. `handleOps` in `abo/src/ops/index.ts` gains the relays. The worker fetch already delegates `OPS_HOST` + `/ops/*`. `opsFetch` stays in `abo/test/system/harness.ts`. `VendorEntrypoint` and `ai-platform/scripts/bootstrap-routing-policy.sh` stay unchanged.

## Consumes Binding

| Consumes | Bound to | This unit |
| --- | --- | --- |
| P4.7 | None. The unit row states no Outputs / freezes line. | Not a frozen contract. `abo/src/ops/index.ts` gains routes. Existing HP verification and `recordOperatorAction` stay as they are for ABO-verified actions. |
| P3.10 | None. The unit row states no Outputs / freezes line. | Not a frozen output to bind. This unit calls the platform methods named in the Read rows. It does not change those methods. |

## Files

| Path | Change | FR |
| --- | --- | --- |
| `abo/src/ops/index.ts` | Relays below. `PLATFORM` on `OpsEnv` gains the methods in Technical Context except paid `grant`, which the existing grant path already calls. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/test/system/configuration-relays.cross-worker.test.ts` | H-XW tests E2E-P4.9-01 through E2E-P4.9-07. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/vitest.cross-worker.config.ts` | Add the new test file to the H-XW `include` list. | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |

No migration. `operator_action` already exists. No change to `abo/src/worker.ts`: `handleOps` there already delegates `/ops/*`.

### Relay shape

Every new route runs the existing `verifyOpsAccess` first. The verified Access JWT is the `access_jwt` forwarded to the platform, with `contract_version` from `CHANNEL_VERSIONS.vendorEntrypoint`. These routes do not use the ABO-side HP verifier and do not call `recordOperatorAction`. The platform writes `control_audit` on the methods that already write it. This unit does not add that write to `supportLookup`.

The body carries `action_id`. The handler inserts one `operator_action` through the existing `insertRelayOperatorAction`, with that id, the Access email as `actor_email`, and the platform `result`. A second insert of the same `action_id` does not run. `action` is the platform method name. `subject` is the credential id, `kid`, `(plan_id, version)`, or request reference in that call.

HP bodies also carry `operation`, `assertion`, and `signer_credential_id`, the same fields the existing console HP relays forward. Bootstrap `registerOperatorCredential` omits those three. The handler still calls the platform method.

The console response returns the platform result, including `code` and `detail` when present.

| Route | Platform method | Class |
| --- | --- | --- |
| `POST /ops/operator-credentials` | `registerOperatorCredential` | HP, or bootstrap |
| `POST /ops/operator-credentials/:credentialId/revoke` | `revokeOperatorCredential` | HP |
| `POST /ops/issuer-keys` | `registerIssuerKey` | HP |
| `POST /ops/issuer-keys/:kid/retire` | `retireIssuerKey` | HP |
| `POST /ops/issuer-keys/:kid/revoke` | `revokeIssuerKey` | HP |
| `POST /ops/service-keys` | `registerServiceKey` | HP |
| `POST /ops/service-keys/:kid/revoke` | `revokeServiceKey` | HP |
| `POST /ops/plan-versions` | `publishPlanVersion` | HP |
| `POST /ops/plan-versions/retire` | `retirePlanVersion` | HP |
| `POST /ops/ceiling-policy` | `setCeilingPolicy` | HP |
| `POST /ops/kill-switches` | `armKillSwitch` | H |
| `POST /ops/routing-policy` | `publishRoutingPolicy` | H |
| `POST /ops/routing-policy/canary` | `canaryRoutingPolicy` | H |
| `POST /ops/routing-policy/promote` | `promoteRoutingPolicy` | H |
| `POST /ops/routing-policy/rollback` | `rollbackRoutingPolicy` | H |
| `POST /ops/cohorts/activate` | `activateCohort` | H |
| `POST /ops/cohorts/promote` | `promoteCohort` | H |
| `POST /ops/capabilities/deprecate` | `deprecateCapability` | H |
| `POST /ops/capabilities/retire` | `retireCapability` | H |
| `POST /ops/token-contracts/begin-rotation` | `beginTokenContractRotation` | H |
| `POST /ops/token-contracts/retire` | `retireTokenContract` | H |
| `GET /ops/support-lookup` | `supportLookup` | H |

Method inputs are the body fields those `VendorEntrypoint` methods already read (`kid`, `public_key`, `not_before`, `not_after`, `plan_id`, `version`, `display_name`, `capabilities`, `max_cost_class`, `concurrency_limit`, `max_allowance_per_month`, the ceiling fields, `document`, `policy_id`, `installation_ids`, `scope`, `target`, `reference`, and the cohort, capability, and token-contract fields). The relay adds `access_jwt` and, on HP, the assertion fields. It does not invent defaults.

`public_key` for issuer and service keys is the base64url encoding of the raw 32-byte Ed25519 public key. Operator registration forwards `credential_id` and the WebAuthn attestation object from the harness.

### Credential bootstrap

E2E-P4.9-01 uses `createSoftwareAuthenticator` from `vendor-contracts/testkit`. The first `opsFetch` sends `attest()` and no approving assertion. The platform raises AL-13 bootstrap: a `platform_alert` row whose `alert_key` is `AL-13:` ‖ credential id ‖ `:bootstrap`. `setClock` then moves the platform test clock 24 hours so that credential is active. The second `opsFetch` sends a new attestation plus `assert()` from the first credential. The new `operator_credential` row is `pending` and `activates_at` is 24 hours ahead. The same session revokes that second credential. The harness does not sleep.

### Issuer drill and service-key switch

E2E-P4.9-03 registers the drill `kid` with `createIssuer`, accepts `POST /v1/requests` with a token for that `kid`, then revokes it. `setClock` advances the platform test clock by the harness `CONFIG_CACHE_TTL_MS` (`100`, within ≤ 30 s). The next token with that `kid` is rejected. The same session calls `retireIssuerKey` on a different `kid` from the drill `kid`.

E2E-P4.9-04 registers the next service key. The key pair is `createAboGrantSigner()`. There is no new binding and no route that sets a secret. The switch reuses the way `runScheduled` already calls `abo/src/worker.ts`: `fetch` and `scheduled` receive the harness env with `ABO_GRANT_KEY` set to the JSON of the key just registered (`kid`, `pkcs8`, `public_key`). Before each of those starts, the test deletes the `signing_key_gate` row so `fetch` runs `maybeRefreshSigningKeyCheck`, the isolate-start check. The paid grant is the existing minute cron `* * * * *` on that env, which runs `runDueGrantWork`. The old `kid` is the harness `ABO_GRANT_KEY` kid. After `revokeServiceKey` on that old `kid`, a further `fetch` on the new key leaves the ABO `alert` row for AL-23 inactive.

### Plan, ceiling, routing, kill switch, and the other class-H relays

E2E-P4.9-02 publishes a plan version, then a paid grant on that version through the existing grant path. The same session calls `setCeilingPolicy` and `retirePlanVersion`. The named assertion is the accepted paid grant.

The platform serves a routing policy when its status is `canary` for a listed installation, or `active` for everyone. `publishRoutingPolicy` inserts `published`, which is not served. E2E-P4.9-05 therefore publishes a document whose target `provider_id` is `fake` (the same shape as `fakePolicyDocument` in `abo/test/system/grant.cross-worker.test.ts`), canaries the fixture installation, then `POST /v1/requests` for that installation expects the fake provider. Promote and rollback follow in that same session. That publish is the console seed that replaces `bootstrap-routing-policy.sh`. The script file stays.

E2E-P4.9-06 arms a kill switch with `scope` `capability` and `target` `clinic.visit_summary`. `POST /v1/requests` for that capability answers `capability_disabled`. AL-19 is a `platform_alert` row. The same session then calls activate cohort, promote cohort, deprecate capability, retire capability, begin token-contract rotation, and retire token contract. Bodies are fixture arguments those methods already accept. The named assertions stay `capability_disabled` and AL-19.

E2E-P4.9-07 looks up a request `reference` from a prior platform request. The relay response includes the envelope from `supportLookup`. `operator_action.actor_email` is the Access email. `supportLookup` is not modified.

## Test Layout

Tests are written first and observed failing. Each title is prefixed with its E2E id. Harness H-XW (`abo/test/system/`, cross-worker vitest, real platform worker from source). Entry is `opsFetch` → `SELF.fetch` on the ABO worker for `OPS_ORIGIN` + `/ops/*`.

| ID | Title prefix | Entry → module chain | Assertion |
| --- | --- | --- | --- |
| E2E-P4.9-01 | `E2E-P4.9-01` | `opsFetch` `POST /ops/operator-credentials` with attestation and no assertion → `handleOps` → `PLATFORM.registerOperatorCredential`. `setClock` +24 h. Second `opsFetch` with a new attestation and the first credential's assertion → the same method. Then `opsFetch` revoke → `PLATFORM.revokeOperatorCredential`. | First call: `platform_alert.alert_key` ends in `:bootstrap` and code is `AL-13`. Second credential row is `pending` with `activates_at` 24 hours ahead. Revoke returns the platform `ok`. One `operator_action` per call, actor the Access email. |
| E2E-P4.9-02 | `E2E-P4.9-02` | `opsFetch` `POST /ops/plan-versions` → `PLATFORM.publishPlanVersion`. Paid grant on that version is the existing `runDueGrantWork` / `PLATFORM.grant` path. Same session: `opsFetch` `POST /ops/ceiling-policy` → `PLATFORM.setCeilingPolicy`, and `opsFetch` `POST /ops/plan-versions/retire` → `PLATFORM.retirePlanVersion`. | The paid grant on the published version is accepted. `operator_action` records publish, ceiling, and retire. |
| E2E-P4.9-03 | `E2E-P4.9-03` | `opsFetch` `POST /ops/issuer-keys` → `PLATFORM.registerIssuerKey`. Token: `PLATFORM_HTTP` `POST /v1/requests` on the real platform worker. `opsFetch` revoke → `PLATFORM.revokeIssuerKey`. `setClock` by `CONFIG_CACHE_TTL_MS`. The same request again. Same session: `opsFetch` retire on a different `kid` → `PLATFORM.retireIssuerKey`. | Token accepted, then rejected after the clock advance. Retire is a different `kid`. `operator_action` records register, revoke, and retire. |
| E2E-P4.9-04 | `E2E-P4.9-04` | `opsFetch` `POST /ops/service-keys` → `PLATFORM.registerServiceKey`. Worker `fetch` and minute `scheduled` with `ABO_GRANT_KEY` set to that key → `maybeRefreshSigningKeyCheck` and `runDueGrantWork`. `opsFetch` revoke of the previous harness kid → `PLATFORM.revokeServiceKey`. A further `fetch` with the new key. | The paid grant is accepted after the switch. After revoke, the further start leaves ABO `alert` for AL-23 inactive. `operator_action` records register and revoke. |
| E2E-P4.9-05 | `E2E-P4.9-05` | `opsFetch` publish → `PLATFORM.publishRoutingPolicy`. `opsFetch` canary → `PLATFORM.canaryRoutingPolicy`. `PLATFORM_HTTP` `POST /v1/requests`. Then `opsFetch` promote and `opsFetch` rollback. | The request is routed to `provider_id` `fake`. `operator_action` records publish, canary, promote, and rollback. |
| E2E-P4.9-06 | `E2E-P4.9-06` | `opsFetch` `POST /ops/kill-switches` → `PLATFORM.armKillSwitch`. Refusal: `PLATFORM_HTTP` `POST /v1/requests`. Same session: the six class-H routes for cohort, capability lifecycle, and token contract. | The capability answers `capability_disabled`. AL-19 is a `platform_alert` row. Each later call writes `operator_action`. |
| E2E-P4.9-07 | `E2E-P4.9-07` | `opsFetch` `GET /ops/support-lookup?reference=` → `handleOps` → `PLATFORM.supportLookup`. | The response includes the envelope. `operator_action.actor_email` is the Access email. |

## Sequencing

1. Add the H-XW test file and its vitest include. Run it and observe E2E-P4.9-01 through E2E-P4.9-07 failing.
2. Extend `PLATFORM` on `OpsEnv` and add the shared forward that writes `operator_action` and returns the platform result.
3. Implement operator-credential register and revoke so E2E-P4.9-01 passes.
4. Implement plan publish, ceiling policy, and plan retire so E2E-P4.9-02 passes. The paid grant stays on the existing grant path.
5. Implement issuer register, revoke, and retire so E2E-P4.9-03 passes.
6. Implement service-key register and revoke so E2E-P4.9-04 passes. The secret switch stays a harness `ABO_GRANT_KEY` value on the existing worker handlers.
7. Implement routing publish, canary, promote, and rollback so E2E-P4.9-05 passes.
8. Implement the kill switch and the cohort, capability, and token-contract routes so E2E-P4.9-06 passes.
9. Implement support lookup so E2E-P4.9-07 passes.
10. After all seven tests pass, implement writes `quickstart.md`. That file is not part of this phase.

## Complexity Tracking

02 §7 records no constitution violation for this unit. No row.
