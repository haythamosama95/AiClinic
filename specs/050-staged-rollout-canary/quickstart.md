# Quickstart: Staged rollout and canary cohorts (J3)

J3 adds operator control-plane mutations for cohort activate / promote of capability builds
and routing-policy publish / canary / roll back, with cohort-aware reads in the router and
capability resolver so named installations receive the staged version while others keep the
previous one — every mutation journaled on `control_audit`.

**Scope rule:** A quickstart documents **this slice only**. List only files this slice added or
modified, only this slice's test files, and only commands that run this slice's tests. Do **not**
include prior-slice files in the review table, combined test counts from earlier slices, prior-slice
regression commands, or diffs "against the <prior slice> baseline". Full-suite regression (this slice
plus every prior slice) belongs in the Verification task, not in `quickstart.md`.

**Numbering rule:** Number sections sequentially (`## 1.`, `## 2.`, …). Section **1** is always
**Architecture context**. When omitting Prerequisites or Manual validation, renumber the remaining
sections — do not leave gaps (e.g. 1, 2, 4, 5).

## 1. Architecture context

J3 implements the **J3** row in
[`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md)
§3.9, covering architecture sections **§12.4** (staged rollout recipes), **§4.5** (control-plane
routing policy and audit), and **§13.4** (promotion / configuration).

- **What the spec delivered** ([`spec.md`](./spec.md)): named-cohort activation for capability
  builds, prompt-backed versions, and routing-policy versions; promotion ending the split;
  rollback-by-deploy for prompts; routing-policy publish / canary / roll back on the control plane;
  `control_audit` on every activation; journal measurability under cohort split.
- **What the plan scoped** ([`plan.md`](./plan.md)): additive `routing_policy.canary_installation_ids`
  migration; extensions to `src/control/`, `src/router/`, `src/capability/`, and `src/worker.ts`;
  two workers-pool pipeline test files; optional `control_audit` assert helper; frozen contract
  `contracts/staged-rollout-canary.md`.

## 2. What was implemented

- **Control-plane cohort and routing mutations** — `POST /control/capabilities/.../activate` and
  `/promote`; `POST /control/routing-policies/.../publish`, `/canary`, `/promote`, and `/rollback`;
  each writes `control_audit` with operator identity (`cohort_activate`, `cohort_promote`,
  `routing_policy_publish`, `routing_policy_canary`, `routing_policy_promote`,
  `routing_policy_rollback`).
- **Installation- and plan-scoped capability grants** — cohort activate updates installation
  `capability_grant` rows; promote raises installation + plan grants and materializes entitled
  installs so the split ends (FR-002).
- **Cohort-aware capability reads** — `discover` and `getGrantedCapabilityVersion` honour
  installation grants with plan-grant fallback under a split.
- **Cohort-aware routing reads** — production `createD1ConfigReader` reconstructs the canary
  split; `preloadRoutingPolicyForInstallation` + installation-keyed `active_routing_policy` cache
  consult; `selectCandidateChain` unchanged after policy resolution.
- **Additive migrations** — `canary_installation_ids` + `status` on `routing_policy` (publish is
  non-serving until canary/promote).
- **Rollback-by-deploy** — prompt / capability rollback re-activates the previous build via grant
  writes (no runtime prompt activation pointer; R-20; structural schema/migration assert in tests).
- **Frozen contract** — [`contracts/staged-rollout-canary.md`](./contracts/staged-rollout-canary.md).

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level
traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/migrations/20260803100000_routing_policy_canary.sql` | Additive `canary_installation_ids` column |
| `ai-platform/migrations/20260805190000_routing_policy_status.sql` | Additive `status` + live grant unique indexes |
| `ai-platform/src/control/routing-policy.ts` | Publish / canary / promote / rollback status machine |
| `ai-platform/src/control/cohort.ts` | Cohort activate / promote (plan + installation grants) |
| `ai-platform/src/control/index.ts` | Dispatch for cohort and routing-policy routes |
| `ai-platform/src/config-cache/index.ts` | Production `createD1ConfigReader` canary-split + grants reads |
| `ai-platform/src/router/index.ts` | Installation-aware active policy preload and cache consult |
| `ai-platform/src/capability/index.ts` | Plan-grant fallback; canary-aware kill-switch provider resolve |
| `ai-platform/src/worker.ts` | `/control` boundary dispatches J3 routes via `isControlRoute` |
| `ai-platform/test/cohort-activate-promote.test.ts` | Named tests `T-J3-01` … `T-J3-03`, `T-J3-05` + plan-promote cases |
| `ai-platform/test/routing-policy-canary.test.ts` | Named test `T-J3-04` plus publish/promote/rollback serving cases |
| `ai-platform/test/helpers/control-audit-assert.ts` | Shared `control_audit` operator-identity helper |
| `specs/050-staged-rollout-canary/contracts/staged-rollout-canary.md` | Frozen routes, audit actions, status semantics |

## 4. Prerequisites

From the repository root:

```bash
cd ai-platform
npm install   # first time only
```

Tests run in the Miniflare D1 (+ R2) workers pool (`vitest.workers.config.ts`); A5, J1, and J3
migrations are applied in `beforeAll`.

## 5. Run the automated suite

From `ai-platform/`:

```bash
npx vitest run --config vitest.workers.config.ts test/cohort-activate-promote.test.ts test/routing-policy-canary.test.ts
```

Expected: **7 passing tests** across the two pipeline files for this slice only. Do **not** run
`npm test` for the full platform suite.

| Test id | Describe name | File |
| --- | --- | --- |
| T-J3-01 | `cohort_receives_new_build_others_previous` | `cohort-activate-promote.test.ts` |
| T-J3-02 | `promotion_moves_all_cohorts` | `cohort-activate-promote.test.ts` |
| T-J3-03 | `rollback_by_deploy_restores_previous_build` | `cohort-activate-promote.test.ts` |
| T-J3-04 | `every_activation_writes_control_audit_with_operator_identity` | `routing-policy-canary.test.ts` |
| T-J3-05 | `journal_records_serving_version_under_cohort_split` | `cohort-activate-promote.test.ts` |

## 6. Inspect the changes

Grep new control actions and canary handlers:

```bash
cd ai-platform
grep -n "cohort_activate\|cohort_promote\|routing_policy_publish\|routing_policy_canary\|routing_policy_rollback" \
  src/control/index.ts
grep -n "canary_installation_ids\|preloadRoutingPolicyForInstallation" \
  src/router/index.ts migrations/20260803100000_routing_policy_canary.sql
grep -n "getGrantedCapabilityVersion" src/capability/index.ts
```

Read the frozen contract:

```bash
cat ../specs/050-staged-rollout-canary/contracts/staged-rollout-canary.md
```

Confirm no runtime prompt activation pointer module exists under `src/` and prompt text is not stored
in D1 — rollback uses grant rewrites via cohort activate of the previous build version.
