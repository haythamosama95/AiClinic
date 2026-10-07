# Console relays: platform configuration, registries and bootstrap

**Unit**: P4.9 · **Harness**: H-XW · **Verification**: T017 green

## 1. What was implemented

Console relays on the ops host forward operator configuration actions to the platform. `handleOps` in `abo/src/ops/index.ts` verifies the Access JWT, records one `operator_action` per call, and calls the matching `PLATFORM` method. HP relays forward `operation`, `assertion`, and `signer_credential_id`; bootstrap `registerOperatorCredential` omits those three while the credential table is empty. Class-H relays forward `access_jwt` only. The platform verifies HP assertions and writes `control_audit` on the methods that already do. Paid grants stay on the existing `runDueGrantWork` / `PLATFORM.grant` path. The ABO secret switch is the harness `ABO_GRANT_KEY` value on the existing worker `fetch` and `scheduled` handlers (FR-001 through FR-011).

- **Configuration relays** (`abo/src/ops/index.ts`) — `POST` routes for operator credentials, issuer keys, service keys, plan versions, ceiling policy, routing policy, kill switches, cohort, capability lifecycle, and token contract. `GET /ops/support-lookup` looks up a request by reference.
- **Vitest include** (`abo/vitest.cross-worker.config.ts`) — adds `test/system/configuration-relays.cross-worker.test.ts` to H-XW.
- **Harness** — seven E2E scenarios in `abo/test/system/configuration-relays.cross-worker.test.ts` (H-XW platform worker). The harness observes every scenario; no manual steps.

### 1.1 Files this unit adds or modifies

| File | FR |
| --- | --- |
| `abo/src/ops/index.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/vitest.cross-worker.config.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `abo/test/system/configuration-relays.cross-worker.test.ts` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010, FR-011 |
| `specs/084-abo-p4-9-console-relays-configuration-registries-bootstrap/quickstart.md` | FR-001–FR-011 |

## 2. Harness command for this unit's tests only

```bash
cd abo && node scripts/build-platform-for-hxw.mjs && vitest run --config vitest.cross-worker.config.ts test/system/configuration-relays.cross-worker.test.ts
```

## 3. Entry point → module chain

| ID | Chain |
| --- | --- |
| E2E-P4.9-01 | `opsFetch` `POST /ops/operator-credentials` with attestation and no assertion → `handleOps` → `PLATFORM.registerOperatorCredential`. `setClock` +24 h. Second `opsFetch` with a new attestation and the first credential's assertion → the same method. Then `opsFetch` revoke → `PLATFORM.revokeOperatorCredential`. First call: `platform_alert.alert_key` ends in `:bootstrap` and code is `AL-13`. Second credential row is `pending` with `activates_at` 24 hours ahead. Revoke returns the platform `ok`. One `operator_action` per call, actor the Access email |
| E2E-P4.9-02 | `opsFetch` `POST /ops/plan-versions` → `PLATFORM.publishPlanVersion`. Paid grant on that version is the existing `runDueGrantWork` / `PLATFORM.grant` path. Same session: `opsFetch` `POST /ops/ceiling-policy` → `PLATFORM.setCeilingPolicy`, and `opsFetch` `POST /ops/plan-versions/retire` → `PLATFORM.retirePlanVersion`. The paid grant on the published version is accepted. `operator_action` records publish, ceiling, and retire |
| E2E-P4.9-03 | `opsFetch` `POST /ops/issuer-keys` → `PLATFORM.registerIssuerKey`. Token: `PLATFORM_HTTP` `POST /v1/requests` on the real platform worker. `opsFetch` revoke → `PLATFORM.revokeIssuerKey`. `setClock` by `CONFIG_CACHE_TTL_MS`. The same request again. Same session: `opsFetch` retire on a different `kid` → `PLATFORM.retireIssuerKey`. Token accepted, then rejected after the clock advance. Retire is a different `kid`. `operator_action` records register, revoke, and retire |
| E2E-P4.9-04 | `opsFetch` `POST /ops/service-keys` → `PLATFORM.registerServiceKey`. Worker `fetch` and minute `scheduled` with `ABO_GRANT_KEY` set to that key → `maybeRefreshSigningKeyCheck` and `runDueGrantWork`. `opsFetch` revoke of the previous harness kid → `PLATFORM.revokeServiceKey`. A further `fetch` with the new key. The paid grant is accepted after the switch. After revoke, the further start leaves ABO `alert` for AL-23 inactive. `operator_action` records register and revoke |
| E2E-P4.9-05 | `opsFetch` publish → `PLATFORM.publishRoutingPolicy`. `opsFetch` canary → `PLATFORM.canaryRoutingPolicy`. `PLATFORM_HTTP` `POST /v1/requests`. Then `opsFetch` promote and `opsFetch` rollback. The request is routed to `provider_id` `fake`. `operator_action` records publish, canary, promote, and rollback |
| E2E-P4.9-06 | `opsFetch` `POST /ops/kill-switches` → `PLATFORM.armKillSwitch`. Refusal: `PLATFORM_HTTP` `POST /v1/requests`. Same session: the six class-H routes for cohort, capability lifecycle, and token contract. The capability answers `capability_disabled`. AL-19 is a `platform_alert` row. Each later call writes `operator_action` |
| E2E-P4.9-07 | `opsFetch` `GET /ops/support-lookup?reference=` → `handleOps` → `PLATFORM.supportLookup`. The response includes the envelope. `operator_action.actor_email` is the Access email |
