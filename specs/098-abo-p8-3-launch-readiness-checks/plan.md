# Implementation Plan: Launch readiness checks

**Branch**: `ai/098-abo-p8-3-launch-readiness-checks` | **Date**: 2026-10-08 | **Spec**: `specs/098-abo-p8-3-launch-readiness-checks/spec.md`

**Input**: Feature specification from `specs/098-abo-p8-3-launch-readiness-checks/spec.md`

## Summary

P8.3 adds a read-only `launch-check` plus the launch runbooks and the section 5 D3 checklist, all in one ops directory. It depends on P8.2 (phase P8, size S). P8.2 freezes nothing, so this unit consumes no module.

## Technical Context

**Language/Version**: Plain Node script (`.mjs`) and markdown, same ops-script shape as `ops/staging/`. No Worker, no Flutter, no SQL.

**Primary Dependencies**: Node built-ins (`node:fs/promises`, `node:test`, `node:child_process`). No new library, package, binding, or config file.

**Storage**: None. The check only reads a target record. It writes no store, no fixture, and no environment.

**Testing**: H-STG. Both rows run `ops/launch/launch-check.mjs`. One `node:test` file in `ops/launch/` carries the titles `E2E-P8.3-01` and `E2E-P8.3-02` (rule V3). That file is not a runner under `e2e/fullstack/`. It does not boot wrangler and does not call Cloudflare, Supabase, or Paymob. A missing live account is expected. The live `launch-check` command against a live staging or production account is not executed in this workflow.

**Target Platform**: Ops scripts and runbooks. Directory recorded here: `ops/launch/`.

**Project Type**: Read-only launch check, six procedure runbooks, and one D3 checklist (05 §6.2, 02 §6, 05 §5, section 5 D3).

**Performance Goals**: One operator runs the check once against one target. No throughput or latency bound is named.

**Constraints**: Read-only. Exit 0 and no failed-condition lines when every FR-001 condition holds. Otherwise exit non-zero and print one line per failed condition, using that condition's existing wording, in FR-001 order. No new condition code and no report schema. E2E-P8.3-02 is one test that runs the same script against each bad target (`workers_dev` re-enabled, then a single active operator credential). The check does not create the bad state. Deletion, the pilot grant, bootstrap, rotation, compromise response, and rebuild stay in the runbooks. A26 stays Partial on the checklist.

**Scale/Scope**: Two H-STG scenarios, eight launch conditions, six runbooks, seven checklist items. Each checklist item has owner developer.

### Target record

`launch-check` reads one JSON file and does not fetch. The file is the target observation. The script applies the FR-001 rules and prints the existing wording below. It does not print a code.

| Observation | Fails when | Printed line |
| --- | --- | --- |
| `control_route`, `operator_bearer_token`, `set_ai_availability`, `manual_entitle_path` | Any is true | No `/control/*` route, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, or manual entitle path exists |
| `workers_dev`, `preview_urls` | Either is true | `workers_dev` and preview URLs are off |
| `channels_version`, `backend_contract_versions_match` | `channels_version` is not 1, or the match flag is not true | Every channel runs contract version 1 on both sides, and the backend's `ai.contract_versions` matches the shared package |
| `al_23_clear`, `key_self_check_passes` | Either is not true | AL-23 is clear. The ABO's key self-check passes. |
| `active_operator_credentials` | Less than 2 | At least two operator credentials are active |
| `issuer_keys_registered`, `service_keys_registered`, `issuer_keys_pinned`, `platform_signing_key_set` | Any is not true | The issuer and service keys are registered. The issuer keys are pinned in the ABO's `ISSUER_KEYS`. The platform signing key is set. |
| `platform_d1_terms`, `platform_d1_grants` | Either is not 0 | Platform D1 holds no terms or grants. |
| `audit_watcher_live`, `heartbeat_monitor_live` | Either is not true | The audit watcher and the heartbeat monitor are live. |

`ops/launch/fixtures/production-like.json` sets every observation to the passing value (`channels_version` 1, counts 0, flags true, `active_operator_credentials` 2). `workers-dev-enabled.json` is that record with `workers_dev` true. `single-operator-credential.json` is that record with `active_operator_credentials` 1. The other observations in each bad record stay passing, so each run names one condition.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-checked after design. 02 §7 records no violation. This unit adds no service, queue, store, or migration.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified
      — 02 §7 principle I and spec §4 Clinic Fit: one operator confirms launch conditions. The check, the runbooks, and the checklist add no clinic workflow and no second architecture.
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service
      — 02 §7 principle I. `launch-check` is one Node script under `ops/launch/`. The runbooks and the checklist are documents.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated
      — 02 §7 principle II and spec §4 Layer Placement. This unit adds no Flutter screen, no Supabase schema, and no Worker write path.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions
      — 02 §7 principle III. The check is read-only. It adds no write path.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving
      — 02 §7 principle IV. The check evaluates `/control` absence, `workers_dev` and previews, credentials, and pinned keys. The checklist records the 02 §4.4 policy. Nothing is hard-deleted by this unit.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable
      — 02 §7 principles II and V. This unit adds no AI action. A failed condition is a named line and a non-zero exit. Rebuild and compromise response stay in the runbooks (05 §5, 02 §6).

## Project Structure

### Documentation (this feature)

```text
specs/098-abo-p8-3-launch-readiness-checks/
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
- Manual steps only if the harness cannot see the behaviour
- The live H-STG command against a live account is not executed in this workflow

### Source Code (repository root)

```text
ops/launch/
├── launch-check.mjs
├── launch-check.test.mjs
├── pre-launch-installation-deletion.md
├── pilot-grant.md
├── bootstrap-ceremony.md
├── rotations.md
├── compromise-response.md
├── rebuilds.md
├── checklist.md
└── fixtures/
    ├── production-like.json
    ├── workers-dev-enabled.json
    └── single-operator-credential.json
```

**Structure Decision**: The recorded directory is `ops/launch/`. It holds the executable, one markdown runbook per procedure, and one checklist. Fixtures and the `node:test` file sit in that same tree so both E2E rows run `launch-check` and this unit adds no runner under `e2e/fullstack/`. No file is added under `abo/`, `ai-platform/`, `backend/`, `frontend/`, `packages/vendor-contracts/`, or `e2e/fullstack/`.

## Consumes Binding

| Consumes | Binding |
| --- | --- |
| P8.2 | None. That unit row states no Outputs / freezes line. |

This unit does not modify a consumed module.

## Files

| Path | Action | FR |
| --- | --- | --- |
| `ops/launch/launch-check.test.mjs` | Create first. `node:test` titles `E2E-P8.3-01` and `E2E-P8.3-02`. Runs `launch-check.mjs` on the fixtures. Does not boot a worker | FR-002, FR-003 |
| `ops/launch/launch-check.mjs` | Create. Read-only. Reads one JSON target. Exit 0 and no failed-condition lines when every rule in Technical Context passes. Otherwise exit non-zero and print the matching lines | FR-001 |
| `ops/launch/fixtures/production-like.json` | Create. Every observation passing | FR-002 |
| `ops/launch/fixtures/workers-dev-enabled.json` | Create. `workers_dev` true; every other observation passing. The check does not write this file | FR-003 |
| `ops/launch/fixtures/single-operator-credential.json` | Create. `active_operator_credentials` 1; every other observation passing. The check does not write this file | FR-003 |
| `ops/launch/pre-launch-installation-deletion.md` | Create. States that pre-launch installations are deleted and that their ledgers stay, per RC-05 | FR-004 |
| `ops/launch/pilot-grant.md` | Create. States the FR-92 grant: 30 days, unit `day`, reason "pre-launch pilot", within the ceilings (03 §3.2), then the clinic buys like everyone else | FR-005 |
| `ops/launch/bootstrap-ceremony.md` | Create. States that the first operator credential is bootstrapped and a second one is registered (24-hour delay) | FR-006 |
| `ops/launch/rotations.md` | Create. States the 02 §6 routine rotation for K-2, K-3, K-4, K-5, K-6, K-7, K-8, and K-10, as written in FR-007. Every credential rotates without an outage | FR-007 |
| `ops/launch/compromise-response.md` | Create. States that a compromised credential is revoked in minutes (SR-11), using the 02 §6 emergency revocation for K-2, K-3, K-4, K-5, K-6, K-7, K-8, and K-10, as written in FR-008 | FR-008 |
| `ops/launch/rebuilds.md` | Create. States the 05 §5 procedures for the ABO (§5.1), a clinic's DO (§5.2), platform D1 (§5.3), and the backend projection (§5.4), as written in FR-009. Each ends with a clean reconciliation run | FR-009 |
| `ops/launch/checklist.md` | Create. Lists the seven section 5 D3 items below. Each item has owner developer | FR-010 |
| `specs/098-abo-p8-3-launch-readiness-checks/quickstart.md` | Implement writes this after harness green, from the outline above | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010 |

Checklist items, each with owner developer:

- RC-06 legal confirmation of the no-refund policy, and R-9 advice on payer contact data and erasure timing (01 §7). These are launch conditions (05 §6.2). The tenancy retrofit (01 R-1) is live, and RC-06 legal confirmation is recorded (01 R-9). R-9 advice on payer contact data is recorded, and the erasure action (§3.2) has been run once in staging.
- 02 §4.4 operating policy: production deploys and secret changes only from an interactive session with hardware-key MFA; no stored token with production rights. This checklist is the P8.3 check. The audit watcher (P8.1) detects breaches. A26 stays Partial.
- IdP hardware-key MFA and 1-hour Access sessions (TB-7, K-8): Access configuration is in P8.1, verified by this checklist.
- Production key generation and registration, bootstrap and second credential, pilot grant (FR-92), and deletion of pre-launch installations: the P8.3 runbooks, run at launch.
- Paymob dashboard settings (callback URLs, integration ids) and HMAC/API key rotation in the dashboard: P8.1/P8.3 runbooks. HMAC and API key rotation follow FR-007 and FR-008 (K-5, K-6).
- NFR-08 plan-allowance confirmation (05 §7) and D1 Time Travel (a built-in feature): recorded in P8.1.
- FR-80 monthly payout CSV import: a routine operator action (05 §10), supported by P4.10.

No file under `e2e/fullstack/`. No edit to `ops/staging/`. No secret value committed.

## Test Layout

The test file is authored first and fails before `launch-check.mjs` and the fixtures exist. One test per id. E2E-P8.3-02 runs the script twice. The harness does not open a live hostname.

| ID | Harness | Entry → chain | Assertion |
| --- | --- | --- | --- |
| E2E-P8.3-01 | H-STG `ops/launch/launch-check.test.mjs` (`node:test`) | `node ops/launch/launch-check.mjs ops/launch/fixtures/production-like.json` | Exit 0 and no failed-condition lines. Every FR-001 condition holds on that record |
| E2E-P8.3-02 | H-STG `ops/launch/launch-check.test.mjs` (`node:test`) | Same script, first on `fixtures/workers-dev-enabled.json`, then on `fixtures/single-operator-credential.json` | Each run exits non-zero and prints that condition's existing wording: `workers_dev` and preview URLs are off; then At least two operator credentials are active. The check does not create either record |

Both rows reach `launch-check.mjs`. The runbooks and the checklist are the documents the Implements line names. They are not a second module.

## Sequencing

1. Author `ops/launch/launch-check.test.mjs` so both titles fail before `launch-check.mjs` and the three fixtures exist.
2. Add `launch-check.mjs`, the three fixtures, the six runbooks, and `checklist.md`.
3. This plan workflow does not run the harness, does not boot wrangler, and does not deploy. Implement runs the command below until it passes, then writes `quickstart.md`. The live command against a live account is not that command and is not executed.

Command, this unit only. It does not boot a worker and it does not call a live account:

- `node --test ops/launch/launch-check.test.mjs`

Do not point this command at earlier suites or at `npm test` in `e2e/fullstack/`.

Task grain for the next phase is one task per path in Files, including the later quickstart task. That is 13 tasks. The work is the files above. It is not padded to the S minimum.

## Complexity Tracking

None. 02 §7 records no constitution violation for this unit.
