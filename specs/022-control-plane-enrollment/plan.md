# Implementation Plan: Control-plane enrollment and installation lifecycle (B2)

**Branch**: `ai/022-b2-control-plane-enrollment` | **Date**: 2026-07-31 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/022-control-plane-enrollment/spec.md`

## Summary

B2 implements the installation-lifecycle control plane of the AI gateway: an operator-authenticated
small internal HTTP surface, separate from the client-facing API, that performs enroll, rotate keys,
suspend, resume, and delete, writing `installation`, `installation_key`, `entitlement`, and a
`control_audit` row carrying the operator identity on every mutation (§4.5, §8.1). It sits in band B
after A5 — the only slice in its `Needs` — because A5 froze those four D1 entities, and it precedes B3
because the guard's entitlement stage reads the installation/entitlement state these mutations produce
(delivery plan §3.3 row B2). Enroll creates the `entitlement` row **pending** with zeroed economics and
an empty, closed period; the economics that decide what a request may cost are written by Entitlement
management, which is out of scope here (§8.1 amendment; §4.5 line-between-rows).

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`); Node ≥22 toolchain. No
new runtime dependency is introduced.

**Primary Dependencies**: `vitest` ~3.2 and the already-present `@cloudflare/vitest-pool-workers`
0.8.71 devDependency (A1 provisioned it) — selected as the harness for the real-Miniflare-D1
integration tests (per Clarification Q3). `wrangler` ~4.86 and `@cloudflare/workers-types` remain as
A1 set them. No schema-validation, auth, or HTTP-framework library is named by §4.5/§8.1; adding one
would be a mechanism the spec does not name (R-20). Lifecycle handlers are plain TS; operator auth is
`createSecretOperatorAuth` (timing-safe secret compare) behind the `OperatorAuth` port.

**Storage**: D1 only, the platform's own store. B2 writes rows into the four entities A5 created
(`installation`, `installation_key`, `entitlement`, `control_audit`); it runs **no** migration and
introduces no new table or column. The A5 migration
`ai-platform/migrations/20260731120000_platform_schema.sql` is applied to the test Miniflare D1 in test
setup, not modified. **Known A5 follow-up:** `UNIQUE(org_id)` on `installation` (not amended here).
B2 does not touch R2 or Durable Objects. Operator Env: `OPERATOR_BEARER_TOKEN` (secret) +
`OPERATOR_ID` (var) — delivery plan §3.3 row B2 `Needs` = A5 only for schema.

**Initial entitlement values (§8.1 amendment, OD-15)**: at enroll the `entitlement` row is created in
status `pending` with: the `plan` name from the enroll payload; `request_quota` = 0, `token_budget` =
0, `cost_budget` = 0; `allowed_capabilities` = empty; `soft_threshold` = 0; `period_start` =
`period_end` = the enrollment instant (a closed, empty period, never an open one). Every column stays
non-null — `pending` is expressed as zeroed budgets and an empty capability set, not absent values
(§7.3 amendment). Entitlement management (out of scope) moves the row to `active` with real economics.
The entitlement status enum is `pending` / `active` / `suspended` (§7.3 amendment); B2 writes
`pending` and `suspended` (suspend/resume toggle `suspended`↔`active`).

**Operator authentication (R-20 reconciled):** §4.5 requires operator identity but names no scheme; no
prior verifying mechanism existed. B2 wires `createSecretOperatorAuth({ bearerToken, operatorId })` —
timing-safe Bearer compare against `OPERATOR_BEARER_TOKEN`, returns configured `OPERATOR_ID` (never
the credential), fail-closed if either Env value is empty. `dispatchControlRequest` requires explicit
`operatorAuth` (no default). Tests inject a fake `OperatorAuth`; e2e uses `SELF.fetch` with Miniflare
bindings. Accept-any Bearer is not permitted.

**Platform base URL (§8.1 return)**: the "enrollment confirmed + platform base URL" reply carries the
gateway's own origin, derived from the request URL — the same Worker serves `/control` and
`/v1/requests`.

**Testing**: `npx vitest run --config vitest.workers.config.ts test/control.test.ts` — Integration
layer (delivery plan §3.11.2 row B2). Harness applies the A5 migration to Miniflare D1 (`env.DB`),
injects fake `OperatorAuth` for handler tests, and covers production wiring via `SELF.fetch` +
Miniflare `OPERATOR_*` bindings. Named cases include T-B2-01..07 (T-B2-05 pins `status === "deleted"`;
T-B2-06/07 pin exact status+body) plus review-resolution cases:
`secret_operator_auth_verifies_credential`, `control_route_end_to_end`, `lifecycle_illegal_transitions`
(5), `suspend_resume_entitlement_unchanged`, `duplicate_enrollment_same_org_different_installation`,
`enroll_invalid_payload`, `rotate_duplicate_kid`, `enroll_invalid_json`, `invalid_route_rejected`,
`installation_not_found`. Full suite + prior bands run in CI (§13.5; §3.10).

**Target Platform**: the `ai-platform/` Cloudflare Worker at the repository root, a sibling of
`frontend/` and `backend/`. B2 is a control-plane mutation surface, not on the AI request hot path.

**Project Type**: Additive, non-primary AI gateway component (§14 acknowledgement) — an operator
control surface over the platform's own D1. No domain logic, no business data, no write path into
Supabase.

**Performance Goals**: The control plane is operator-invoked and rare (tens of installations); no
latency budget applies and none is named (§9.14). The platform's per-request I/O budgets (one Quota DO
round trip, one D1 insert in the guard, one R2 object per request — §6.1, §7.5, §13.6) are untouched
because B2 is not on the request path. Coverage is behavioural (§3.10): row writes, audit identity,
rejections, and the one-time/rotation invariants are asserted by query, not by timing.

**Constraints**:
- The control plane is "a small internal surface, separate from the client-facing API and separately
  authenticated (operator identity, not clinic identity)" (§4.5). Operator-driven, never self-service
  (§8.1; OD-7).
- Enrollment is one-time per clinic installation; a duplicate enroll produces no second installation
  and resolves deterministically (§8.1; spec Edge Cases). The architecture names no §5.4 code for the
  control plane; rejection is the specified outcome, not a code (spec Edge Cases).
- Rotation adds a new `kid` row without removing the previous one, so both keys are accepted during
  the overlap (§8.1); verifying both keys is the guard's concern (B3), not B2's.
- Every control-plane mutation is journaled as a `control_audit` row carrying the operator identity
  (§4.5). Routing policy and kill-switch audits are the highest-leverage actions; B2 establishes the
  `control_audit.action` vocabulary for lifecycle actions, which J3/F3 extend and never rewrite
  (delivery plan §2.3).
- No mechanism from §9.14 is added; no per-request server-side state; no retry, caching, or
  configurability beyond what §4.5/§8.1 name (R-20; spec Out of Scope).

**Scale/Scope**: One §4 component — §4.5 Control plane. Sibling modules under `src/control/`, Worker
route + `OPERATOR_*` Env, one test file, workers vitest config, contract + quickstart.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — operator-driven
      enrollment of tens of installations; no billing/pricing engine, no plan catalogue (OD-15
      default: "not initially"), no enterprise-only machinery.
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — the control plane is a small HTTP surface on the
      existing single deployable Worker (A1); no new service, queue, DO class, or cron is introduced.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — B2 lives wholly
      in `ai-platform/` and touches neither `frontend/` nor `backend/`. The platform owns its own D1
      separately from the clinic Supabase (§4.4; §3.4). Per the §14 acknowledgement, the Worker is an
      additive, non-primary component with no domain logic, no business data, and no write path into
      Supabase.
- [ ] (intentionally unchecked — see note) Protected writes, validation, permissions, and
      transactional rules remain enforced through PostgreSQL constraints, triggers, RLS, or RPC
      functions — N/A: B2 writes the platform's **own** D1, not the clinic Supabase. The clinic
      Supabase's RLS, RPCs, triggers, and `audit_log` are untouched. The platform D1's integrity is
      held by the A5 migration's `PRIMARY KEY` and `FOREIGN KEY` constraints and by the
      `control_audit` row on every mutation; this row concerns the Supabase/PostgreSQL layer, which
      the additive gateway does not replace.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — authenticated (operator identity, §4.5, via the
      `OperatorAuth` port); auditable (every mutation writes `control_audit` carrying the operator
      identity, §4.5); soft-delete-preserving (delete is a lifecycle status transition that writes an
      audit row, not a row purge — the installation-by-`installation_id` purge is owned by F3 per
      A5's data-model §4.2). Tenant-scoped/branch-scoped are deliberately *not* properties of the
      control plane: an operator manages installations *across* tenants, so operator-scope is the
      correct layering above clinic-tenant scope, which is enforced on the client-facing path by B3.
- [ ] (intentionally unchecked — see note) AI actions remain human-approved, have no direct
      database/backend access, and the feature still works in a degraded manual mode when AI is
      unavailable — N/A: B2 declares no AI action, has no AI request path, and has no clinical content
      to gate. Control-plane unavailability does not block clinical workflows because AI is strictly
      additive (A11) and the client hides affordances when the platform is unreachable (§14); this row
      concerns the AI-request/acceptance runtime owned by later slices.

The two unchecked boxes are the PostgreSQL-enforcement and AI-action-runtime rows that are
structurally inapplicable to a control-plane slice in the additive gateway. They are not constitution
violations; they are recorded here rather than silently dropped, per the §14 acknowledgement that the
gateway is non-primary, additive, and holds no domain truth.

## Project Structure

### Documentation (this feature)

```text
specs/022-control-plane-enrollment/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify output (already present)
├── quickstart.md        # Written after implementation + verification (this slice's review surface)
├── contracts/
│   └── control-plane.md # Frozen lifecycle surface: routes, action vocabulary, operator-auth rule,
│                       # enroll entitlement initial values (§8.1 amendment), entitlement status enum
│                       # (§7.3 amendment), rotation overlap invariant — bound by B3 guard, J3, F3
└── tasks.md            # /ai-platform-tasks output (NOT created here)
```

`quickstart.md` **is** produced — every slice produces one (plan rule). Sections it will contain (per
`.specify/templates/ai-platform-quickstart-template.md`): **1. Architecture context** (§4.5 + §8.1,
delivery plan §3.3 row B2, what the spec/plan scoped); **2. What was implemented** (the five lifecycle
handlers, the `/control` route, the `OperatorAuth` port, the `pending` enrollment entitlement); **3.
Files to review** (`src/control/` siblings + barrel, `src/worker.ts` diff, `test/control.test.ts`,
`vitest.workers.config.ts`, `contracts/control-plane.md`); **4. Prerequisites** — Miniflare workers
pool + `OPERATOR_BEARER_TOKEN` secret / `OPERATOR_ID` var for local Worker runs; **5. Run the automated suite**
(`npx vitest run --config vitest.workers.config.ts test/control.test.ts`); **6. Inspect the changes**
(read lifecycle FSM + auth, grep rejection codes, read frozen entitlement initial-values contract); no
**7. Manual validation** section (CI is the only verification path — the
control plane has no user-facing behaviour beyond the suite).

`data-model.md` is **not** produced — B2 defines no D1 entities (spec §Key Entities); it writes into
the entities A5 froze (A5's `specs/019-…-…/data-model.md` is consumed unchanged). The
entitlement-status enum and enroll initial values live in `contracts/control-plane.md` as the
contract extension B2 freezes (§7.3/§8.1 amendments), not in a new data-model file, so A5's frozen
artifact is not rewritten (delivery plan §2.3).

`contracts/` **is** produced — the Freezes block establishes a wire-shape surface (the `/control` HTTP
routes and the `control_audit.action` lifecycle vocabulary) plus the `pending` initial-entitlement
snapshot the guard reads. B3's `Consumes` will bind to the status enum and audit vocabulary, and J3/F3
extend them (each is "may extend, never rewrite", §2.3), so they must bind to an artifact, not prose.

`research.md` is never produced on this platform; the research is
`docs/architecture/17-ai-platform.md` (delivery plan §6, plan-phase protocol).

### Source Code (repository root)

```text
ai-platform/
├── vitest.config.ts                    # A1 — consumed unchanged (default Node pool for prior suites)
├── vitest.workers.config.ts            # workers-pool harness; Miniflare OPERATOR_* bindings for e2e
├── wrangler.toml                       # OPERATOR_ID var per env; OPERATOR_BEARER_TOKEN via secret put
├── migrations/
│   └── 20260731120000_platform_schema.sql  # A5 — consumed unchanged (UNIQUE(org_id) = known follow-up)
├── src/
│   ├── worker.ts                       # /control → createSecretOperatorAuth(Env) + dispatchControlRequest
│   └── control/                        # sibling-per-concern modules + barrel index.ts
│       ├── index.ts                    # barrel + isControlRoute / dispatchControlRequest
│       ├── types.ts
│       ├── http.ts
│       ├── auth.ts                     # createSecretOperatorAuth (timing-safe; fail-closed)
│       ├── audit.ts                    # writeAudit (non-batched; token-contract)
│       ├── lifecycle.ts                # enroll/rotate/suspend/resume/delete (audit in batch)
│       ├── capability-lifecycle.ts
│       ├── cohort.ts
│       ├── routing-policy.ts
│       ├── token-contract.ts
│       └── support-purge.ts
└── test/
    └── control.test.ts                 # T-B2-01..07 + review-resolution cases
```

**Structure Decision**: `ai-platform/src/control/` sibling modules behind barrel `index.ts` (Clarification
Q2). Production Worker builds `createSecretOperatorAuth` from `OPERATOR_BEARER_TOKEN` + `OPERATOR_ID`
and passes it explicitly to `dispatchControlRequest`. Tests inject fake `OperatorAuth`; e2e uses
`SELF.fetch` with Miniflare bindings. Harness in `vitest.workers.config.ts` (shared `vitest.config.ts`
untouched).

## Consumes Binding

| **Consumes** entry | Existing module / file bound to | How B2 binds to it |
| --- | --- | --- |
| A5 — platform D1 logical model: every §7.3 entity present after forward-only migration, including `installation`, `installation_key`, `entitlement`, `control_audit` (A5 `Freezes`; delivery plan §3.2 row A5 "Done when"). | `ai-platform/migrations/20260731120000_platform_schema.sql` (the forward-only migration creating the four entities and their `PRIMARY KEY`/`FOREIGN KEY` constraints) and `ai-platform/schema.snap.sql` (the frozen DDL). | B2 inserts into those four tables exactly as A5 created them — same column names, same NOT NULL/FK constraints, the `control_audit` row shape (`audit_id`, `operator_id`, `action`, `target`, `before_pointer`, `after_pointer`, `recorded_at`). B2 imports no A5 module at runtime (the handlers write D1 directly through the `DB` binding); the binding is the **schema** A5 froze. The migration and snapshot are read in test setup (applied to the workers-pool Miniflare D1) and never modified — delivery plan §2.3. The entitlement status enum (`pending`/`active`/`suspended`, §7.3 amendment) and the enroll initial values (§8.1 amendment) were added to the architecture **after** A5 shipped; B2 extends the frozen column with these values in its own `contracts/control-plane.md` rather than editing A5's artifact (extension, not rewrite — §2.3). |

The bound migration exists on disk (verified). No Consumes entry lacks an implementation; satisfying
the spec does not require modifying A5's migration, snapshot, `config-cache/`, `context/`, or any A1–A4
module — stop condition 2 is not triggered.

## Components Touched

| §4 component | What B2 changes | Behaviour added? |
| --- | --- | --- |
| §4.5 Control plane | B2 realises the "Installation lifecycle" row ("Enroll, rotate keys, suspend, resume, delete") and the audit rule ("Every control-plane mutation is journaled with the operator identity") on the platform's own D1, and freezes the enroll entitlement write (the line between this row and "Entitlement management", §4.5 amendment). | Yes — the first behavioural write path into `installation`/`installation_key`/`entitlement`/`control_audit`. This is B2's whole scope. No other §4 component is changed: §4.2 clinic-side keystore/issuer is B1; §4.3 guard, §4.3.3 entitlement enforcement, and §4.4's read-through cache are B3/B4; §4.1 client is untouched. |

B2 touches exactly one §4 component — §4.5 Control plane. No written reason for touching multiple
components is needed; none is.

## Files

| Path | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/control/` (`types`, `http`, `auth`, `audit`, `lifecycle`, barrel `index.ts`, plus later-slice siblings) | Created / split | FR-001…FR-011 — `OperatorAuth` / `createSecretOperatorAuth`, five lifecycle handlers (FSM + payload/D1 error mapping), enroll `pending` entitlement, rotation overlap, audit journaling of `OPERATOR_ID`, explicit `dispatchControlRequest(…, operatorAuth)`. |
| `ai-platform/src/worker.ts` | Modified | FR-001, FR-002, FR-009 — `/control` dispatch; wires Env `OPERATOR_BEARER_TOKEN` + `OPERATOR_ID` into `createSecretOperatorAuth`; no default auth. |
| `ai-platform/wrangler.toml` | Modified | FR-009 — `OPERATOR_ID` var per env; `OPERATOR_BEARER_TOKEN` supplied via `wrangler secret put` (not committed). |
| `ai-platform/vitest.workers.config.ts` | Created | SC-001…004 + review cases — workers pool, Miniflare `DB` + `OPERATOR_*` bindings. |
| `ai-platform/test/control.test.ts` | Created | T-B2-01…07 (T-B2-05 pins `deleted`; T-B2-06/07 pin status+body) + `secret_operator_auth_verifies_credential`, `control_route_end_to_end`, `lifecycle_illegal_transitions`, `suspend_resume_entitlement_unchanged`, `duplicate_enrollment_same_org_different_installation`, `enroll_invalid_payload`, `rotate_duplicate_kid`, `enroll_invalid_json`, `invalid_route_rejected`, `installation_not_found`. |
| `specs/022-control-plane-enrollment/contracts/control-plane.md` | Created | Freezes — `/control` surface, lifecycle actions, secret operator-auth rule, `pending` enroll entitlement, status enum, rotation overlap, rejection table §2.4, FSM terminal rules. |
| `specs/022-control-plane-enrollment/quickstart.md` | Created (implement phase) | Documentation slice review surface (not traced to an FR; template-mandated). |

No file is traced to a `## Clarifications` entry. Clarification Q2's sibling-per-concern layout is the
current source layout. `OPERATOR_BEARER_TOKEN` is a Workers secret (not committed plaintext).

## Test Layout

Named tests from the spec's `### Test plan` run in the Integration layer (delivery plan §3.11.2 row
B2). Harness: `vitest.workers.config.ts` + `test/control.test.ts` — A5 migration on Miniflare `env.DB`;
fake `OperatorAuth` for handler calls; `SELF.fetch` + Miniflare `OPERATOR_*` for route e2e.

| Spec Test plan name | Test id | File | Layer | Asserts (FR / SC) |
| --- | --- | --- | --- | --- |
| `enroll_writes_all_four_tables` | T-B2-01 | `test/control.test.ts` | Integration | FR-005/FR-006 / SC-001 — four-table enroll; `pending` entitlement; gateway origin. |
| `lifecycle_suspend_audit` | T-B2-02 | `test/control.test.ts` | Integration | FR-008 / SC-002 — suspend audit + `installation.status = suspended`. |
| `lifecycle_resume_audit` | T-B2-03 | `test/control.test.ts` | Integration | FR-008 / SC-002 — resume audit + restore `active` from `suspended`. |
| `lifecycle_rotate_audit` | T-B2-04 | `test/control.test.ts` | Integration | FR-007 / SC-002 — new `kid`, previous kept, rotate audit. |
| `lifecycle_delete_audit` | T-B2-05 | `test/control.test.ts` | Integration | FR-008 / SC-002 — delete audit; **`status === "deleted"`**. |
| `non_operator_credentials_rejected` | T-B2-06 | `test/control.test.ts` | Integration | FR-001/FR-009 / SC-003 — **`401` + `{error:"unauthorized"}`**; no D1 writes. |
| `duplicate_enrollment_deterministic` | T-B2-07 | `test/control.test.ts` | Integration | FR-004/FR-010 / SC-004 — **`409` + `{error:"already_enrolled"}`**; row counts unchanged. |
| `secret_operator_auth_verifies_credential` | — | `test/control.test.ts` | Integration | FR-009 — wrong/missing bearer → null; match → `OPERATOR_ID` ≠ credential; empty config fail-closed. |
| `control_route_end_to_end` | — | `test/control.test.ts` | Integration | FR-001 — `SELF.fetch` route → handler → D1; journals `OPERATOR_ID`. |
| `lifecycle_illegal_transitions` | — | `test/control.test.ts` | Integration | FR-008 — five cases → `409 illegal_lifecycle_transition`. |
| `suspend_resume_entitlement_unchanged` | — | `test/control.test.ts` | Integration | FR-008 — entitlement row unchanged across suspend/resume. |
| `duplicate_enrollment_same_org_different_installation` | — | `test/control.test.ts` | Integration | FR-010 — same `org_id`, different id → `409 already_enrolled`. |
| `enroll_invalid_payload` | — | `test/control.test.ts` | Integration | FR-011 — `400 invalid_payload`. |
| `rotate_duplicate_kid` | — | `test/control.test.ts` | Integration | FR-011 — `409 duplicate_kid`. |
| `enroll_invalid_json` | — | `test/control.test.ts` | Integration | Contract §2.4 — `400 invalid_json`. |
| `invalid_route_rejected` | — | `test/control.test.ts` | Integration | Contract §2.4 — `400 invalid_route`. |
| `installation_not_found` | — | `test/control.test.ts` | Integration | Contract §2.4 — `404 installation_not_found`. |

## Sequencing

1. **`ai-platform/vitest.workers.config.ts`** — define the scoped workers-pool config
   (`@cloudflare/vitest-pool-workers`, `miniflare.d1Databases` binding `DB` against an ephemeral
   SQLite, `compatibilityDate` matching `wrangler.toml`, `include: ["test/control.test.ts"]`). Lands
   first because the test harness gates every later step; the shared `vitest.config.ts` is untouched so
   prior suites keep their Node pool.
2. **`ai-platform/test/control.test.ts` (skeleton + `beforeAll`)** — add the `beforeAll` that reads
   `ai-platform/migrations/20260731120000_platform_schema.sql` and applies it to `env.DB` (the A5
   migration, unmodified), and the fake `OperatorAuth` factory (fixed principal / `null`). Land the
   harness-before-handlers per the "tests alongside or before, never after" rule.
3. **`ai-platform/src/control/index.ts` — `OperatorAuth` port + enroll handler** — define the
   `OperatorAuth` port (per Clarification Q2) and the enroll handler that writes the four rows
   transactionally: `installation` (lifecycle status = active-enrolled / pending-trust as §8.1),
   `installation_key` (public key + `kid` + algorithm), `entitlement` (status `pending`, plan from
   payload, zeroed economics, closed empty period per §8.1 amendment), `control_audit`
   (`action = enroll`, operator identity), and returns the gateway origin. Write T-B2-01 and T-B2-07
   alongside this branch.
4. **`ai-platform/src/control/index.ts` — rotate / suspend / resume / delete handlers** — implement
   the four remaining lifecycle mutations, each writing its `control_audit` row; rotate keeps the
   previous `installation_key` row and adds a new `kid`. Write T-B2-02/03/04/05 alongside each branch.
5. **`ai-platform/src/control/index.ts` — non-operator rejection** — ensure every handler consults
   `OperatorAuth` first and writes no row + returns a terminal rejection on `null`. Write T-B2-06
   alongside.
6. **`ai-platform/src/worker.ts`** — add the `/control` route dispatch with operator-auth gating that
   routes to the handlers (per Clarification Q1); `/v1/requests` and `/health` unchanged. An end-to-end
   fetch assertion is folded into T-B2-01 (route → handler → D1).
7. **Run `npx vitest run --config vitest.workers.config.ts test/control.test.ts`** — T-B2-01..07 green.
   Then run the prior suites under the default config `npx vitest run` and confirm every band-A/B1 suite
   stays green (§3.10 checkpoint rule: every prior suite green, not just the latest).
8. **`specs/022-control-plane-enrollment/contracts/control-plane.md`** — freeze the `/control` surface
   (routes), the five `control_audit.action` lifecycle values, the operator-auth requirement, the
   `pending` enroll entitlement initial values (§8.1 amendment), the entitlement status enum
   (`pending`/`active`/`suspended`, §7.3 amendment, including the guard's "pending reads as no
   capability allowed → quota-exhaustion path"), and the rotation overlap invariant — so B3/J3/F3 bind
   to an artifact, not prose.
9. **`specs/022-control-plane-enrollment/quickstart.md`** — fill from
   `.specify/templates/ai-platform-quickstart-template.md` (sections 1–6 per the Documentation box
   above; no Manual validation section — CI is the only verification path).

Tests land alongside or before each handler branch (steps 3–5 interleave with the handler
implementation; the harness in steps 1–2 precedes all of them). The Documentation artifacts
(steps 8–9) are written only after the suite is green — the plan names them here, the implement phase
fills them in.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. The two unchecked Constitution
> boxes are recorded above as structurally inapplicable to a control-plane slice in the additive
> gateway (per the §14 acknowledgement), not as violations.