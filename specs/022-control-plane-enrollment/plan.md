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
would be a mechanism the spec does not name (R-20). The lifecycle handlers are plain TS functions; the
`OperatorAuth` port is a single-method seam (per Clarification Q2).

**Storage**: D1 only, the platform's own store. B2 writes rows into the four entities A5 created
(`installation`, `installation_key`, `entitlement`, `control_audit`); it runs **no** migration and
introduces no new table, column, index, or binding. The A5 migration
`ai-platform/migrations/20260731120000_platform_schema.sql` is applied to the test Miniflare D1 in test
setup, not modified. B2 does not touch R2, Durable Objects, or the secrets binding (delivery plan §3.3
row B2 `Needs` = A5 only).

**Initial entitlement values (§8.1 amendment, OD-15)**: at enroll the `entitlement` row is created in
status `pending` with: the `plan` name from the enroll payload; `request_quota` = 0, `token_budget` =
0, `cost_budget` = 0; `allowed_capabilities` = empty; `soft_threshold` = 0; `period_start` =
`period_end` = the enrollment instant (a closed, empty period, never an open one). Every column stays
non-null — `pending` is expressed as zeroed budgets and an empty capability set, not absent values
(§7.3 amendment). Entitlement management (out of scope) moves the row to `active` with real economics.
The entitlement status enum is `pending` / `active` / `suspended` (§7.3 amendment); B2 writes
`pending` and `suspended` (suspend/resume toggle `suspended`↔`active`).

**Operator authentication**: an established, out-of-band credential external to this slice (spec
Assumptions; §4.5 "operator identity, not clinic identity"). B2 consumes an `OperatorAuth` port that
resolves an operator principal from the incoming request or rejects; the real scheme is not
implemented here and none is invented (R-20). The fake `OperatorAuth` in tests returns a fixed operator
principal or `null` (per Clarification Q3).

**Platform base URL (§8.1 return)**: the "enrollment confirmed + platform base URL" reply carries the
gateway's own origin, derived from the request URL — the same Worker serves `/control` and
`/v1/requests`. No new binding or secret is introduced for it.

**Testing**: `npx vitest run --config vitest.workers.config.ts test/control.test.ts` — the only test
file, in the Integration layer (delivery plan §3.11.2 row B2). The harness applies the A5 migration to
a per-test Miniflare D1 (`env.DB`) in `beforeAll`, injects the fake `OperatorAuth`, exercises the
lifecycle handlers from `ai-platform/src/control/`, and asserts row writes by querying `env.DB` back.
No HTTP read-back route is invented (that would be an untraced surface). The full slice suite plus all
prior band suites run in CI on every change (§13.5; §3.10 checkpoint rule).

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

**Scale/Scope**: One §4 component — §4.5 Control plane. One source module (`src/control/`), one worker
route addition, one test file, one scoped vitest config, one contract artifact, one quickstart.
Roughly 16–18 tasks (well under the ~25 ceiling of delivery plan §6.3 / plan stop condition 5).

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
Files to review** (`src/control/index.ts`, `src/worker.ts` diff, `test/control.test.ts`,
`vitest.workers.config.ts`, `contracts/control-plane.md`); **4. Prerequisites** — kept: the tests need
the `@cloudflare/vitest-pool-workers` Miniflare D1 pool, so the `--config vitest.workers.config.ts`
flag and a one-time `npm install` are stated; **5. Run the automated suite**
(`npx vitest run --config vitest.workers.config.ts test/control.test.ts`); **6. Inspect the changes**
(read the lifecycle handlers, grep `control_audit.action` cases, read the frozen entitlement
initial-values contract); no **7. Manual validation** section (CI is the only verification path — the
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
├── vitest.workers.config.ts            # NEW — scoped workers-pool harness for the D1 integration tests
├── migrations/
│   └── 20260731120000_platform_schema.sql  # A5 — consumed unchanged (applied in test setup, never edited)
├── src/
│   ├── worker.ts                       # MODIFIED — add /control route dispatch to src/control
│   └── control/                        # NEW — control-plane lifecycle (per Clarification Q2)
│       └── index.ts                    # exports enroll/rotate/suspend/resume/delete + OperatorAuth port
└── test/
    └── control.test.ts                 # NEW — T-B2-01 .. T-B2-07 integration tests (real Miniflare D1)
```

**Structure Decision**: One new module `ai-platform/src/control/` mirroring A4's `src/manifest/` and
A5's `src/context/` (sibling-per-concern, per Clarification Q2), exporting the five lifecycle handlers
and the `OperatorAuth` port. The `/control` routes are wired in `src/worker.ts` (operator-auth
middleware resolves the principal then dispatches), keeping the surface visibly separate from the
client-facing `/v1/requests` adapter (§4.5 "separate from the client-facing API", per Clarification
Q1). The harness lives in a **separate** `vitest.workers.config.ts` so the shared
`vitest.config.ts` (A1's default Node pool used by every prior suite) is untouched; only
`test/control.test.ts` opts into the `@cloudflare/vitest-pool-workers` pool with a Miniflare `DB`
binding (per Clarification Q3 — a real Miniflare D1 for write assertions + a fake `OperatorAuth`).
No `wrangler.toml` change — A1 provisioned the per-environment `DB` binding; the workers-pool harness
declares its own ephemeral Miniflare D1 in the config, and `src/worker.ts`'s binding assertion is
unaffected.

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
| `ai-platform/src/control/index.ts` | Created | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-010 — the `OperatorAuth` port, the five lifecycle handlers, the enroll write set with `pending` initial entitlement values (§8.1 amendment), the rotation overlap (new `kid`, previous row kept), suspend/resume/delete status transitions + audit, non-operator rejection, and one-time duplicate-enrollment rejection. |
| `ai-platform/src/worker.ts` | Modified | FR-001, FR-002 — `/control` HTTP routes dispatched to `src/control/` with operator-auth gating before any mutation (per Clarification Q1); the client-facing `/v1/requests` and `/health` routes are unchanged. |
| `ai-platform/vitest.workers.config.ts` | Created | SC-001, SC-002, SC-003, SC-004 — the scoped `@cloudflare/vitest-pool-workers` pool with an ephemeral Miniflare `DB` binding enabling the real-D1 write assertions named by the test plan (per Clarification Q3). |
| `ai-platform/test/control.test.ts` | Created | SC-001 (T-B2-01 enroll writes all four tables), SC-002 (T-B2-02/03/04/05 suspend/resume/rotate/delete audit), SC-003 (T-B2-06 non-operator rejected), SC-004 (T-B2-07 duplicate enrollment deterministic — unchanged D1 row count + non-2xx response, per Clarification Q4). |
| `specs/022-control-plane-enrollment/contracts/control-plane.md` | Created | Freezes — the `/control` surface, the five `control_audit.action` lifecycle values, the operator-auth requirement, the `pending` enroll entitlement initial values (§8.1 amendment), the entitlement status enum (§7.3 amendment), and the rotation overlap invariant; bound by B3 (guard reads `pending` as "no capability allowed" → quota-exhaustion path), J3 (control_audit activations), F3 (installation purge references the lifecycle status). |
| `specs/022-control-plane-enrollment/quickstart.md` | Created (implement phase) | Documentation slice review surface (not traced to an FR; template-mandated). |

No file is traced to a `## Clarifications` entry. The four implementation choices (HTTP routes under
`/control`, the `src/control/` module, the real-Miniflare-D1 + fake-`OperatorAuth` harness, the
duplicate-enrollment dual assertion) are followed in the layout and harness above but never promoted
into a requirement (delivery plan §6 "downstream contract"). No `ai-platform/wrangler.toml` change —
A1 provisioned the `DB` binding; no new binding, secret, namespace, or DO class is added.

## Test Layout

All seven named tests from the spec's `### Test plan` run in the Integration layer named by delivery
plan §3.11.2 row B2, realised via the §13.5 "Pipeline tests" harness style (deterministic, real
Miniflare D1). The harness is `vitest.workers.config.ts` + `test/control.test.ts` (per Clarification
Q3): `beforeAll` applies the A5 migration to the workers-pool Miniflare `env.DB`; each test injects a
fake `OperatorAuth` (fixed principal or `null`), calls a `src/control/` handler, then asserts rows by
querying `env.DB` back. A prior-slice read-back route is not invented.

| Spec Test plan name | Test id | File | Layer | Asserts (FR / SC) |
| --- | --- | --- | --- | --- |
| `enroll_writes_all_four_tables` | T-B2-01 | `test/control.test.ts` | Integration | FR-005/FR-006 / SC-001 — enroll with operator credentials + org info + public key + plan writes exactly one row each in `installation`, `installation_key`, `entitlement` (status `pending`, zeroed economics, closed empty period per §8.1 amendment), and `control_audit` (operator identity, `action = enroll`); reply carries the gateway origin base URL. |
| `lifecycle_suspend_audit` | T-B2-02 | `test/control.test.ts` | Integration | FR-008 / SC-002 — suspend writes `control_audit` with operator identity and sets `installation.status = suspended`. |
| `lifecycle_resume_audit` | T-B2-03 | `test/control.test.ts` | Integration | FR-008 / SC-002 — resume writes `control_audit` with operator identity and restores the prior active lifecycle status. |
| `lifecycle_rotate_audit` | T-B2-04 | `test/control.test.ts` | Integration | FR-007 / SC-002 — rotate adds a new `installation_key` row with a new `kid`, leaves the previous row present (overlap intact), and writes `control_audit` with operator identity. |
| `lifecycle_delete_audit` | T-B2-05 | `test/control.test.ts` | Integration | FR-008 / SC-002 — delete writes `control_audit` with operator identity and transitions lifecycle status; the row purge itself is out of scope (F3). |
| `non_operator_credentials_rejected` | T-B2-06 | `test/control.test.ts` | Integration | FR-001/FR-009 / SC-003 — with `OperatorAuth` returning `null`, each of the five mutations produces no D1 row write and a terminal rejection (no §5.4 code; spec Edge Cases). |
| `duplicate_enrollment_deterministic` | T-B2-07 | `test/control.test.ts` | Integration | FR-004/FR-010 / SC-004 — a second enroll for an existing `installation`/`org_id` leaves the D1 row count unchanged and returns a terminal non-2xx rejection (per Clarification Q4 — both sides asserted). |

All seven named tests place cleanly in the Integration layer; none is left unplaced (stop condition 3
not triggered). Coverage from §3.10: the happy path of every requirement is T-B2-01..05; B2 emits no
§5.4 error code (spec Edge Cases), so there are no per-code cases; every branch (non-operator rejection
T-B2-06, one-time duplicate T-B2-07) and every named boundary (one-time enrollment §8.1, rotation
overlap §8.1) is covered; inherited prohibitions (no per-request state, no §9.14 mechanism) are
respected by design and asserted by the absence of any such object in `src/control/`.

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