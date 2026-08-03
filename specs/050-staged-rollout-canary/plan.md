# Implementation Plan: Staged rollout and canary cohorts (J3)

**Branch**: `ai/050-j3-staged-rollout-canary` | **Date**: 2026-08-03 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/050-staged-rollout-canary/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

J3 adds deferred band-J compatibility behaviour for staged rollout: an operator activates a new
capability build, prompt-backed capability version, or routing-policy version for a named cohort so
that cohort receives the new build while others stay on the previous one; promotes so all cohorts
move onto the activated version; rolls prompts/capability builds back by deploying the previous
build; and publishes / canaries / rolls back routing-policy versions on the operator-authenticated
control plane — every such mutation a `control_audit` row with the operator identity. Under a cohort
split the journal already records serving versions (prompt hash / capability version / policy
version). It sits in band J after B2, D1, D2, and F1 (`Needs: B2, D1, D2, F1`); build when a prompt,
capability version, or routing policy has an audience that can be split (delivery plan §3.9 row J3;
DP-5).

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`), `target: ES2022`,
strict, `@cloudflare/workers-types` — matching B2/D1/D2/C1.

**Primary Dependencies**: existing `ai-platform/src/control/` (B2 — `OperatorAuth`,
`dispatchControlRequest`, `writeAudit` / `control_audit` insert pattern); `ai-platform/src/router/`
(D2 — `selectCandidateChain`, `RoutingDecision`, `active_routing_policy` consult); 
`ai-platform/src/capability/` (C1 — `resolve`, `discover`, installation-scoped `grants` via
`loadConfig`); `ai-platform/src/prompt/` (D1 — immutable registry + composer; prompt version /
`prompt_artifact_hash` for the journal); `ai-platform/test/eval/` (F1 — CI golden gate, consumed not
redefined); `ai-platform/src/config-cache/` (A5 — `active_routing_policy`, `grants`). No new runtime
dependency; no schema-validation or HTTP-framework library (R-20).

**Storage**: Platform D1 (+ R2 for immutable routing-policy documents under
`control/routing-policy/{policy_id}/{version}.json` per §4.3.7). No new D1 **entity**. Cohort
activation for capability builds / prompt-backed versions uses existing installation-scoped
`capability_grant` rows. Routing-policy publish writes a new `routing_policy` row + R2 object;
canary / promote / roll back select which version is active per installation. One **forward-only
additive migration** may add a nullable `canary_installation_ids` TEXT column on `routing_policy`
(JSON array of installation ids for an in-canary version; `NULL` = not canary-scoped / promoted
global active) so cold-isolate config reads reconstruct the split without inventing a cohort table —
same “extend existing entity, no new entity” pattern as J1’s overlay columns. Prompts, manifests,
and schemas remain deployed Worker artifacts (FR-008; §13.4; no runtime prompt activation pointer —
§9.5 / §9.14 / R-20). No Quota DO or Supabase write.

**Testing**: Separate Pipeline suites (Clarification session 2026-08-03 Q3):
`npx vitest run --config vitest.workers.config.ts test/cohort-activate-promote.test.ts` and
`npx vitest run --config vitest.workers.config.ts test/routing-policy-canary.test.ts` — Integration /
Pipeline layer (delivery plan §3.11.8 row J3; §13.5 Pipeline tests). Real Miniflare D1 (+ R2 for
policy documents), A5 (+ J1 / J3 additive) migrations in setup, B2-style fake `OperatorAuth`,
optional shared `control_audit` assert helper. Both files registered in **both** harness configs —
`vitest.workers.config.ts` `include` and `vitest.config.ts` `exclude` — so `npx vitest run` (§3.10)
stays green (B2/C1/J1 precedent). Slice-only; suite joins CI permanently.

**Target Platform**: the `ai-platform/` Cloudflare Worker at the repository root (sibling of
`frontend/` and `backend/`). Control-plane mutate path plus cohort-aware stage-5 resolve and router
reads; no Flutter or Supabase domain path.

**Project Type**: Additive, non-primary AI gateway component (§14 acknowledgement) — no domain
logic, no business data, no write path into Supabase, always optional.

**Performance Goals**: Control mutations are operator-rare (off Quota DO / R2 request budgets).
Request-path cohort selection reads through the existing config cache (`grants`,
`active_routing_policy`) — no second D1 round trip on a warm isolate, no second Quota DO fetch, no
second R2 object per request, no per-request server-side state (§4.4, §7.5, §9.7, §13.6). Journal
serving-version columns are those C3/D1/D2 already write (`prompt_artifact_hash`,
`capability_version`, `routing_decision.policy_version`).

**Constraints**:
- Named cohort = operator-supplied set of installation ids on the mutation (audit `target` /
  payload); not a new cohort entity (spec Key Entities).
- Prompt / capability-build rollback is **by deploy** of the previous build — no runtime prompt
  activation pointer (FR-003; §12.4; §9.5 deferred; R-20).
- Routing-policy publish / canary / roll back are control-plane mutations with `control_audit`
  (FR-004, FR-005; §4.5).
- F1 CI golden gate must pass before a regressing prompt is staged (FR-009); J3 does not redefine
  goldens, scores, or live smoke (F1 Freezes).
- Chain selection rules, fake adapter, prompt composition, and B2 enroll/suspend/resume/rotate/
  delete / `control_audit` **row shape** are not rewritten (delivery plan §2.3).
- No Flutter prompt/provider/model strings (R-12); no §9.14 mechanism; no new request-path taxonomy
  code (spec Edge Cases).

**Scale/Scope**: Three §4 components (§4.5 Control plane, §4.3.7 Provider router, §4.3.4 Capability
resolver) — see **Components Touched** for the written reason. Optional one additive migration,
extensions to `src/control/`, `src/router/`, `src/capability/`, two new pipeline test files, one
optional shared audit helper, one contract artifact, one named quickstart. Roughly 18–22 tasks
(under the ~25 ceiling of delivery plan §6.3 / plan stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — named-cohort
      canary then promote matches clinic-scale incident containment without enterprise fleet
      management (constitution I; §12.4; §13.4 Promotion; spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — extend B2 control handlers and cohort-aware
      reads on existing cache kinds; no new service, queue, or DO class.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — J3 lives
      wholly in `ai-platform/`; no Flutter surface; no Supabase write.
- [ ] (intentionally unchecked — see note) Protected writes, validation, permissions, and
      transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC
      functions — N/A: J3 writes the platform's **own** D1 (`routing_policy`, `capability_grant`,
      `control_audit`) and R2 policy objects, not clinic Supabase. Integrity is existing PKs/FKs,
      the optional additive column, and B2's operator-authenticated audit rule. This row concerns
      the Supabase/PostgreSQL layer.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — mutations are operator-authenticated (B2
      `OperatorAuth`, not clinic identity); every activation / promote / canary / roll back writes
      `control_audit` with the operator identity (FR-005); no hard-delete of clinic data.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — a bad prompt or policy
      is contained by cohort canary and undone by rollback/deploy rather than locking clinical work;
      gateway unavailability never blocks clinical work (constitution V; §14).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no
domain logic, no business data, and no write path into Supabase. J3 only extends platform D1/R2
activation state, control audit, and cohort-aware resolve / router reads of that state.

The one unchecked box is the Supabase/PostgreSQL-enforcement row that is structurally inapplicable
to a gateway D1 control / resolve slice. It is not a constitution violation; it is recorded here
rather than silently dropped.

## Project Structure

### Documentation (this feature)

```text
specs/050-staged-rollout-canary/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify (+ clarify) output (authoritative)
├── contracts/
│   └── staged-rollout-canary.md  # Freezes: cohort activate/promote, rollback-by-deploy,
│                                 # routing-policy publish/canary/roll back, control_audit
│                                 # action vocabulary extensions, journal serving-version
│                                 # measurability under split
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — J3 defines **no new D1 entity** (spec Key Entities). Optional
additive `canary_installation_ids` on A5's `routing_policy` and installation-scoped
`capability_grant` usage are frozen in `contracts/staged-rollout-canary.md` so later slices bind to
an artifact without rewriting A5's `specs/019-…/data-model.md` (delivery plan §2.3).

`research.md` is **never** produced on this platform — the research is
`docs/architecture/17-ai-platform.md`.

`contracts/` **is** produced — Freezes entries have wire / table / audit shapes (control routes and
`control_audit.action` extensions, cohort activate/promote payloads, routing-policy publish/canary/
roll back, rollback-by-deploy rule, journal version columns under split) that later slices'
**Consumes** must bind to.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — J3 row of the delivery plan (§3.9) and Implements (§12.4, §4.5,
  §13.4); what the spec delivered; what the plan scoped.
- **§2 What was implemented** — control-plane Routing policy + cohort activate/promote handlers;
  cohort-aware D2/C1 reads; optional additive `routing_policy` column; rollback-by-deploy for
  prompts; `control_audit` on every activation.
- **§3 Files to review** — this slice's migration (if any), `src/control/index.ts` diff,
  `src/router/index.ts` diff, `src/capability/index.ts` diff, the two pipeline test files,
  `contracts/staged-rollout-canary.md`.
- **§4 Prerequisites** — Miniflare D1 (+ R2) workers pool (`vitest.workers.config.ts`); one-time
  `npm install` in `ai-platform/`.
- **§5 Run the automated suite** — slice-only:
  `npx vitest run --config vitest.workers.config.ts test/cohort-activate-promote.test.ts
  test/routing-policy-canary.test.ts`.
- **§6 Inspect the changes** — grep new `control_audit.action` values / canary handlers; read the
  frozen contract; confirm no runtime prompt activation pointer and no prompt text in D1.
- No **§7 Manual validation** — CI is the only verification path beyond the suite.

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   ├── 20260731120000_platform_schema.sql              # A5 — unchanged (consumed)
│   ├── 20260802100000_capability_grant_lifecycle.sql   # J1 — unchanged (consumed)
│   └── 20260803100000_routing_policy_canary.sql        # NEW (if needed) — additive
│                                                       #   canary_installation_ids (FR-004, FR-008)
├── schema.snap.sql                                     # MODIFIED — reflect additive column
├── src/
│   ├── control/
│   │   └── index.ts                                    # MODIFIED — routing-policy publish /
│   │                                                   #   canary / roll back; cohort activate /
│   │                                                   #   promote; audit + dispatch (FR-001..005,
│   │                                                   #   FR-007, FR-010, FR-011)
│   ├── router/
│   │   └── index.ts                                    # MODIFIED — cohort-aware active policy
│   │                                                   #   resolution for installation; chain
│   │                                                   #   selection unchanged (FR-001, FR-004,
│   │                                                   #   FR-011)
│   ├── capability/
│   │   └── index.ts                                    # MODIFIED — cohort-aware granted build
│   │                                                   #   via installation-scoped grants
│   │                                                   #   (FR-001, FR-002, FR-007, FR-010)
│   ├── prompt/                                         # UNCHANGED — D1 registry/composer consumed
│   ├── journal/                                        # UNCHANGED — already records versions
│   ├── config-cache/                                   # UNCHANGED — reuse grants +
│   │                                                   #   active_routing_policy kinds
│   └── worker.ts                                       # MODIFIED — /control routes for new
│                                                       #   mutations
├── test/
│   ├── cohort-activate-promote.test.ts                 # NEW — prompt/capability-build cohort
│   │                                                   #   activate / promote / rollback-by-deploy
│   │                                                   #   + journal version (Clarification Q3)
│   ├── routing-policy-canary.test.ts                   # NEW — publish / canary / roll back +
│   │                                                   #   control_audit (Clarification Q3)
│   └── helpers/
│       └── control-audit-assert.ts                     # NEW (optional) — shared control_audit
│                                                       #   operator-identity assert helper
├── vitest.workers.config.ts                            # MODIFIED — include both new test files
└── vitest.config.ts                                    # MODIFIED — exclude both from Node pool
```

**Structure Decision**: Extend B2's `src/control/` in place for all J3 mutations (Clarification Q1).
Cohort-aware request-path selection lives inside existing D2 router and C1 capability resolver —
each continues to return the active policy / granted build for that installation; **no new pipeline
stage** (Clarification Q2). Separate pipeline test modules for prompt/capability-build vs
routing-policy canary (Clarification Q3). F1's `test/eval/` harness is consumed unchanged as the CI
gate before staged prompt deploy (FR-009).

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How J3 binds to it |
| --- | --- | --- |
| **B2** — operator-authenticated control-plane surface; every mutation journaled as `control_audit` with operator identity | `ai-platform/src/control/index.ts` — `OperatorAuth`, `OperatorPrincipal`, `dispatchControlRequest`, audit insert pattern; `ai-platform/src/worker.ts` `/control` dispatch. Frozen artifact: `specs/022-control-plane-enrollment/contracts/control-plane.md`. | J3 **extends** the control plane with Routing policy publish / canary / roll back and cohort activate / promote handlers that reuse `OperatorAuth` and write `control_audit` with new `action` values (B2 explicitly allows later slices to extend the action vocabulary for routing-policy activations). It does **not** redefine enroll / rotate / suspend / resume / delete or the `control_audit` row shape. B2's contract file is not edited. |
| **D1** — immutable prompt artifacts deployed with the Worker and pinned by the capability manifest; prompt version recorded on the journal | `ai-platform/src/prompt/registry.ts`, `ai-platform/src/prompt/composer.ts`; artifacts under `ai-platform/prompts/`. Frozen artifact: `specs/028-prompt-registry-composer/contracts/composer-output.md`. | J3 activates / promotes / rolls back **builds** by cohort deploy + capability-version grants; it does **not** store prompt text in D1, invent an editable-prompt path, or redefine composition. Rollback of a prompt change is by deploying the previous build (FR-003). Journal continues to record resolved `prompt_artifact_hash` / prompt version (FR-006). D1 modules are not rewritten. |
| **D2** — versioned routing-policy-as-data; router reads active policy and records selection reason | `ai-platform/src/router/index.ts` — `selectCandidateChain`, `RoutingDecision`, `RouterContext`. Frozen artifact: `specs/029-provider-port-routing/contracts/routing-decision.md` (and `provider-port.md` unchanged). | J3 **extends** active-policy resolution so an installation under a canary split receives the cohort's policy version; chain filtering, fake adapter, and “no provider history” rules are **not** redefined. D2's contract files are not edited. |
| **F1** — capability eval harness that gates prompt / capability changes in CI | `ai-platform/test/eval/` (`harness.ts`, `golden.test.ts`, …); `.github/workflows/ci.yml` golden gate. Frozen artifact: `specs/039-eval-suite-harness/contracts/capability-eval-harness.md`. | J3 activates staged prompt / capability builds **only after** that gate; it does not redefine golden cases, score recording, or scheduled live smoke. No `src/eval/` module is introduced. F1's contract file is not edited. |

No consumed entry lacks an implementation. None of the frozen Consumes contracts is rewritten
(delivery plan §2.3).

**Clarification-driven placement (not Consumes):** cohort-aware granted-build reads also extend
`ai-platform/src/capability/index.ts` (C1 — `resolve` / `discover` + `grants` cache kind). C1 is not
a Consumes rewrite target; J3 uses installation-scoped `capability_grant` rows A5/C1 already expose
and does not change registry key format or the three resolver taxonomy codes.

## Components Touched

| §4 component | What J3 changes | Behaviour added? |
| --- | --- | --- |
| §4.5 Control plane | **Extended** — Routing policy publish / canary / roll back; cohort activate / promote for capability builds (and prompt-backed versions via grants); every mutation `control_audit` with operator identity. | Yes — §4.5 Routing policy row and §12.4 staged recipes. |
| §4.3.7 Provider router | **Extended** — resolve which routing-policy **version** is active for this installation under a cohort split; then existing chain selection / selection reason unchanged. | Yes — Clarification Q2; FR-001, FR-004, FR-011. |
| §4.3.4 Capability resolver | **Extended** — resolve which granted capability **build/version** serves this installation under a cohort split (installation-scoped grants); discovery surfaces the granted build. | Yes — Clarification Q2; FR-001, FR-002, FR-007, FR-010. |

**Written reason for touching three §4 components:** J3's Done when and §12.4 recipes require both
halves of staged rollout: (1) operator control-plane mutations that publish / canary / activate /
promote / roll back and write `control_audit`, and (2) request-path selection so the named cohort
receives the new build while others receive the previous one, with the journal recording which
version served. Clarifications Q1–Q2 place (1) on the existing B2 control-plane module and (2) as
cohort-aware reads inside the existing D2 router and C1 capability resolver with no new pipeline
stage. Delivery plan §3.9 Needs (`B2, D1, D2, F1`) plus those placement decisions span control plane
+ router + resolver; no single §4 component alone satisfies the slice. Stop condition 5 is satisfied
by this reason; task count stays ~18–22.

No other §4 component is touched (prompt registry/composer consumed unchanged; journal already
records versions; Quota DO / Flutter / providers unchanged).

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/migrations/20260803100000_routing_policy_canary.sql` | Created (if additive column required) | FR-004, FR-008 — `ALTER TABLE routing_policy ADD` nullable `canary_installation_ids` for cohort-scoped activation of a policy version. |
| `ai-platform/schema.snap.sql` | Modified | FR-004, FR-008 — snapshot matches post-migration `routing_policy` shape when the additive column lands. |
| `ai-platform/src/control/index.ts` | Modified | FR-001, FR-002, FR-003, FR-004, FR-005, FR-007, FR-010, FR-011 — handlers for routing-policy publish / canary / roll back and cohort activate / promote; installation-scoped `capability_grant` writes; R2 policy object write on publish; `control_audit` actions; `dispatchControlRequest` / `isControlRoute` extensions. |
| `ai-platform/src/router/index.ts` | Modified | FR-001, FR-004, FR-006, FR-011 — cohort-aware resolution of which `active_routing_policy` document applies to `RouterContext.installationId`; `selectCandidateChain` / filtering / selection-reason shape unchanged. |
| `ai-platform/src/capability/index.ts` | Modified | FR-001, FR-002, FR-006, FR-007, FR-010 — cohort-aware granted build for the installation (grants under split); resolve/discover continue to return the granted active build; no new taxonomy codes. |
| `ai-platform/src/worker.ts` | Modified | FR-004, FR-005 — dispatch new `/control/...` paths to control handlers (same `/control` boundary B2 froze). |
| `ai-platform/test/cohort-activate-promote.test.ts` | Created | SC-001, SC-002, SC-003, SC-005 — named tests for prompt/capability-build cohort activate / promote / rollback-by-deploy and journal serving version (Clarification Q3). |
| `ai-platform/test/routing-policy-canary.test.ts` | Created | SC-001, SC-002, SC-003, SC-004 — named tests for routing-policy publish / canary / roll back and `control_audit` identity (Clarification Q3). |
| `ai-platform/test/helpers/control-audit-assert.ts` | Created (optional) | FR-005 / SC-004 — shared assert helper for `control_audit` operator identity (Clarification Q3). |
| `ai-platform/vitest.workers.config.ts` | Modified | — `include` adds both new test files. |
| `ai-platform/vitest.config.ts` | Modified | — `exclude` adds both so the default Node pool does not load Miniflare-D1 tests. |
| `specs/050-staged-rollout-canary/contracts/staged-rollout-canary.md` | Created | Freezes cohort activate/promote, rollback-by-deploy, routing-policy publish/canary/roll back, `control_audit.action` extensions, journal version measurability (FR-001..FR-011 Freezes). |
| `specs/050-staged-rollout-canary/quickstart.md` | Created (implement phase) | — template-mandated review surface; sections named above. Not traced to an FR. |

Every code/contract file traces to an `FR-###`. Consumed modules' frozen contracts
(`control-plane.md`, `composer-output.md`, `routing-decision.md`, `capability-eval-harness.md`) are
**not** modified. No untraced file. No runtime prompt activation pointer module.

## Test Layout

The spec's Test plan names five tests at §13.5 **Pipeline tests** (delivery plan §3.11.8 J3 layer
**Integration** → active policy and build selection under cohort activation). Per Clarification Q3
they split across two modules (optional shared audit helper).

| Spec Test plan name | Test id | §13.5 layer | File / config | Asserts (FR / SC) |
| --- | --- | --- | --- | --- |
| A cohort receives the new build while others receive the previous one | T-J3-01 | Pipeline tests | `test/cohort-activate-promote.test.ts` (`vitest.workers.config.ts`) | FR-001, FR-008, FR-010 / SC-001 — after cohort activate of a capability/prompt build, cohort installations resolve the new build; non-cohort installations resolve the previous one. |
| Promotion moves all cohorts | T-J3-02 | Pipeline tests | `test/cohort-activate-promote.test.ts` | FR-002, FR-007 / SC-002 — after promote, all installations receive the activated build; no residual split. |
| Rollback restores the previous build | T-J3-03 | Pipeline tests | `test/cohort-activate-promote.test.ts` | FR-003 / SC-003 — rollback **by deploy** of the previous build restores prior serving for affected cohorts; no runtime prompt activation pointer exists. |
| Every activation writes a `control_audit` row with the operator identity | T-J3-04 | Pipeline tests | `test/routing-policy-canary.test.ts` (+ cohort suite cases that mutate) | FR-005 / SC-004 — activate / promote / canary / roll back each write `control_audit` with that operator id; optional shared helper. |
| The journal records which version served each request under the cohort split | T-J3-05 | Pipeline tests | `test/cohort-activate-promote.test.ts` (and routing suite for `policy_version`) | FR-006 / SC-005 — under split, journaled `prompt_artifact_hash` / capability version (and routing `policy_version`) match the build each cohort received. |

Additional coverage implied by §3.10 / FR-004 / FR-009 / FR-011 (same two files, not extra FR-traced modules):
- Routing-policy publish → canary cohort receives new policy version; others keep previous; promote ends split; roll back restores previous policy version (`test/routing-policy-canary.test.ts`).
- Non-operator credentials rejected under B2's operator-auth rule (consumed; one assert in each suite).
- Staged prompt activate fixtures assume F1 golden gate (FR-009) — no bypass path; do not redefine F1 harness.
- Inherited prohibitions: no runtime prompt activation pointer; no per-request server-side state; no second Quota DO / R2 on the request path.

Every named test places in a §13.5 layer — stop condition 3 not triggered.

## Sequencing

Tests land first or alongside implementation, never after (delivery plan §2.2):

1. **Contract** — `contracts/staged-rollout-canary.md` freezes routes, audit actions, cohort payload
   shape, rollback-by-deploy rule, and journal version assertions before handlers land.
2. **Migration (FR-004, FR-008)** — additive `canary_installation_ids` (if required) +
   `schema.snap.sql` so D1 can reconstruct routing canary splits.
3. **Control-plane handlers (FR-001..005, FR-007, FR-010, FR-011)** — publish / canary / roll back /
   activate / promote + `control_audit`; T-J3-04 and routing canary cases driven through mutations
   (alongside tests).
4. **Cohort-aware router + capability reads (FR-001, FR-002, FR-006, FR-011)** — T-J3-01 / T-J3-02 /
   T-J3-05 against seeded grants / active policy; no new pipeline stage.
5. **Rollback-by-deploy path (FR-003, FR-009)** — T-J3-03 restores previous build via deploy
   simulation; confirm F1 gate remains the CI precondition for staged prompt changes.
6. **Documentation** — `quickstart.md` last, during the implement-phase Documentation task, after
   the slice's tests pass.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. The one unchecked
> Constitution box is recorded above as structurally inapplicable to a gateway D1 slice (per the
> §14 acknowledgement), not as a violation.
