# Contract: Staged rollout and canary cohorts (J3)

**Frozen by:** Slice J3 — Staged rollout and canary cohorts
**Implements:** §12.4, §4.5, §13.4 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices **may extend, never rewrite** the cohort activate / promote
surface, the rollback-by-deploy rule for prompts / capability builds, the routing-policy publish /
canary / roll back control functions, the `control_audit.action` values added here, or the journal
serving-version measurability under a cohort split (delivery plan §2.3).

**Source of truth in code:** `ai-platform/src/control/index.ts` (mutations + audit);
`ai-platform/src/router/index.ts` (cohort-aware active policy resolution);
`ai-platform/src/capability/index.ts` (cohort-aware granted build);
optional `ai-platform/migrations/20260803100000_routing_policy_canary.sql`.

**Traces to:** FR-001 … FR-011; spec Freezes. Consumes B2
(`specs/022-control-plane-enrollment/contracts/control-plane.md`), D1
(`specs/028-prompt-registry-composer/contracts/composer-output.md`), D2
(`specs/029-provider-port-routing/contracts/routing-decision.md`), and F1
(`specs/039-eval-suite-harness/contracts/capability-eval-harness.md`) without rewriting them.

---

## 1. Overview

J3 freezes staged rollout / canary behaviour:

1. A new **capability build**, **prompt-backed capability version**, or **routing-policy version**
   MAY be activated for a **named cohort** so that cohort receives the new build while others keep
   the previous one (§12.4; §13.4 Promotion).
2. **Promotion** moves all cohorts onto the activated version and ends the split (§12.4).
3. A **prompt** (and capability-build) change is rolled back by **deploying the previous build** —
   never via a runtime prompt activation pointer (§12.4; §9.5 deferred; R-20).
4. **Routing policy** publish / canary / roll back are control-plane functions, separately
   authenticated by operator identity (§4.5).
5. Every activation, promotion, canary, or roll back writes a **`control_audit`** row with the
   operator identity (B2 Freezes applied).
6. Under a cohort split, the **journal records which version served** each request (prompt hash /
   capability version / `routing_decision.policy_version`) so the change is measurable afterwards
   (§12.4; D1 Freezes).

A named cohort is an operator-supplied set of installation ids on the mutation. This slice defines
**no cohort entity**.

---

## 2. Control-plane HTTP surface (extensions)

All routes remain `POST` only on the existing `/control` boundary (B2). Operator auth is the B2
`OperatorAuth` port; non-operator credentials are rejected with no D1 write.

| Route (illustrative) | Purpose | D1 / R2 writes |
| --- | --- | --- |
| `POST /control/routing-policies/{policy_id}/versions/{version}/publish` | Publish a new versioned policy document | `routing_policy` row + R2 object at `control/routing-policy/{policy_id}/{version}.json` (§4.3.7); `control_audit` |
| `POST /control/routing-policies/{policy_id}/versions/{version}/canary` | Activate that version for a named cohort | Cohort-scoped activation on `routing_policy`; `control_audit` |
| `POST /control/routing-policies/{policy_id}/versions/{version}/rollback` | Roll back to the previous active version | Reactivate prior version; clear canary split; `control_audit` |
| `POST /control/capabilities/{capability_id}/versions/{version}/activate` | Activate a capability build for a named cohort | Installation-scoped `capability_grant` rows for cohort members; `control_audit` |
| `POST /control/capabilities/{capability_id}/versions/{version}/promote` | Promote so all cohorts receive the activated version | Expand grants / end split; `control_audit` |

Exact path strings may match the implementer's `dispatchControlRequest` patterns so long as they
stay under `/control`, reuse `OperatorAuth`, and write `control_audit`. B2 lifecycle routes are
unchanged.

### 2.1 Cohort payload

Activate / canary mutations carry a named cohort as installation ids (and an optional operator label
for audit `target`):

| Field | Required | Meaning |
| --- | --- | --- |
| `installation_ids` | yes | Non-empty list of installation ids that receive the new version |
| `cohort_name` | no | Operator label recorded on the audit target / after pointer |

Non-listed installations **MUST** remain on the previous build until promotion (§12.4; FR-001).

### 2.2 Rejection responses

Same non-§5.4 control-plane rejection style as B2 (`401 unauthorized`, `400` malformed,
`404` missing target). J3 emits **no** new §5.4 taxonomy codes on the request path.

---

## 3. `control_audit.action` vocabulary (extensions)

B2's five lifecycle actions and J1's `deprecate` / `retire` remain. J3 **extends** with:

| `action` | Mutation |
| --- | --- |
| `routing_policy_publish` | Publish a new versioned routing policy |
| `routing_policy_canary` | Canary a policy version to a named cohort |
| `routing_policy_rollback` | Roll back routing policy to the previous version |
| `cohort_activate` | Activate a capability / prompt-backed build for a named cohort |
| `cohort_promote` | Promote so all cohorts move onto the activated version |

Each row carries B2's frozen columns (`audit_id`, `operator_id`, `action`, `target`,
`before_pointer`, `after_pointer`, `recorded_at`). An activation without a `control_audit` row
carrying the operator identity is forbidden (§4.5; FR-005).

---

## 4. Capability / prompt-backed cohort activation

### 4.1 Durable effect

Activation for a named cohort writes **installation-scoped `capability_grant`** rows (A5 entity;
existing columns) for each cohort installation id → `(capability_id, capability_version)`.
Promotion expands that grant so all relevant installations receive the activated version and the
staged split ends (FR-002).

Prompt artifacts remain **deployed Worker assets** pinned by the capability manifest (D1 Freezes;
FR-008). Both the previous and new builds MAY be present in the Worker; grants select which
capability version (hence which pinned prompt hash) an installation receives. This is **not** a
runtime prompt activation pointer (§9.5).

### 4.2 Rollback by deploy

Rolling back a prompt / capability-build change **MUST** deploy the previous build (restore prior
pinned artifacts / default grants). J3 **MUST NOT** introduce a D1 or config-cache pointer that
selects prompt text independently of deploy (§12.4; FR-003; R-20).

### 4.3 Request-path read

`resolve` / `discover` continue to return the **granted build for that installation**
(Clarification Q2). Under a cohort split, cohort members and non-members may receive different
capability versions; no new pipeline stage is added.

### 4.4 Eval gate

A prompt change that fails the F1 eval suite **MUST NOT** be activated for a cohort (FR-009).
J3 consumes `specs/039-eval-suite-harness/contracts/capability-eval-harness.md` and does not
redefine goldens, scores, or live smoke.

---

## 5. Routing-policy publish / canary / roll back

### 5.1 Publish

Publishing creates:

1. An immutable R2 object at `control/routing-policy/{policy_id}/{version}.json` (document shape
   remains D2's frozen policy document — chain selection rules unchanged).
2. A `routing_policy` row (`policy_id`, `version`, `content_pointer`, `active_from`,
   `activated_by`) plus `control_audit`.

### 5.2 Canary and promote

Canary activates the published version for the named cohort only. Other installations keep the
previously promoted active version. Promotion makes the version the global active policy and clears
the canary split (FR-002, FR-004).

Optional additive column on `routing_policy` (no new entity):

| Column | Type | Nullable | Meaning |
| --- | --- | --- | --- |
| `canary_installation_ids` | TEXT | Yes | JSON array of installation ids for which this version is canary-active; `NULL` = not canary-scoped (promoted / global semantics). |

A5 columns are otherwise unchanged. Cold-isolate config reads reconstruct the split via
`active_routing_policy` without a second entity kind.

### 5.3 Roll back

Routing-policy roll back reactivates the previous version through the control plane (not by editing
the immutable R2 document) and writes `control_audit` (FR-004, FR-005).

### 5.4 Request-path read

The provider router resolves which policy **version** is active for
`RouterContext.installationId`, then runs existing `selectCandidateChain` / filtering / selection
reason (Clarification Q2; D2 Freezes). `RoutingDecision.policy_version` continues to identify the
serving version on the journal (FR-006, FR-011).

---

## 6. Journal measurability under cohort split

Under a cohort split, each completed request's journal **MUST** record the serving version so the
effect of the change is measurable (FR-006):

| Signal | Store | Source |
| --- | --- | --- |
| Prompt / artifact version | `ai_request.prompt_artifact_hash` (and structured logs' prompt version) | D1 composer / registry resolution |
| Capability version | `ai_request.capability_version` | Resolved / granted build |
| Routing policy version | `ai_request.routing_decision` → `policy_version` | D2 selection reason |

J3 does not add journal columns; it asserts these existing fields differ correctly across cohorts
when versions differ.

---

## 7. Prohibitions (inherited, restated)

- No runtime prompt activation pointer (§9.5 / §9.14; R-20).
- No prompt text, provider name, or model identifier in the Flutter client (R-12).
- No per-request server-side state (§4.4, §9.7).
- No second Quota DO round trip and no second R2 object on the **request** path (§7.5, §13.6).
  (Control-plane publish may write one R2 policy object — operator-rare, off the request budget.)
- No rewrite of B2 lifecycle actions, D1 composition, D2 chain selection, or F1 harness internals
  (delivery plan §2.3).
