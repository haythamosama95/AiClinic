# Implementation Plan: Plan catalogue and credit-denominated entitlement (G1)

**Branch**: `ai/056-g1-plan-catalogue` | **Date**: 2026-09-11 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/056-plan-catalogue/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

G1 adds the small operator-maintained plan catalogue, the versioned `credit_price` table (created, not activated), and the entitlement monthly credit-budget column (`credit_budget`) inside the Cloudflare AI Gateway Worker. Assignment reads the catalogue and copies plan economics onto a pending installation entitlement in one audited mutation; plans and entitlements are served through the A5 config cache. It sits in Band G after A5 and B2 (`Needs: A5, B2`); G2 cannot debit a monthly credit budget that does not yet exist.

## Technical Context

**Language/Version**: TypeScript 5.9 (`ai-platform/package.json`) targeting the Cloudflare Worker; D1 SQLite via forward-only Wrangler migrations. Node `>=22` for the Vitest / Wrangler harness.

**Primary Dependencies**: A5 D1 schema snapshot + in-isolate config cache (`ai-platform/src/config-cache/index.ts` — `ConfigCache`, `loadConfig`, `D1Reader`, `ConfigCacheMissError`, `ConfigEntityKind`, `createD1ConfigReader`); B2 operator-authenticated control plane (`ai-platform/src/control/` — `OperatorAuth` / `createSecretOperatorAuth`, `requireOperator`, `reject` / `ok` / `parseJsonBody`, `runControlBatch` / `writeAudit`, `dispatchControlRequest` / `isControlRoute`, `lifecycle.ts` enroll write set). I4 `handleEntitle` (`src/control/entitle.ts`, `POST /control/installations/:id/entitle`) is the Entitlement-management path this slice extends with catalogue reads (Delivery Plan §3.13); I4 is not in **Consumes** and grant/revoke / self-heal are not rewritten. No new npm packages, no Supabase schema, no Flutter surface (V4 later).

**Storage**: Platform D1 only. Forward-only additive migration creates `plan`, `credit_price`, `entitlement.credit_budget INTEGER NOT NULL DEFAULT 0`, and `entitlement.max_cost_class TEXT NOT NULL DEFAULT ''` (the §7.3 field assignment copies; A5 omitted it from the physical table). Enroll INSERT is unchanged: SQLite `DEFAULT` keeps every column non-null while pending (zeroed credit budget, empty `max_cost_class`). No FK from `entitlement.plan` to `plan.name` — enroll still writes the plan name before a catalogue row exists. `credit_price` is created empty; G4 is the first activation writer. Config cache owns nothing; D1 remains authority.

**Testing**: SQL / migration in the existing A5 Wrangler-local harness (`ai-platform/test/migrations.test.ts`) for `migrations_apply_cleanly_empty_database` and `schema_snapshot_matches`. Workers integration (`npx vitest run --config vitest.workers.config.ts`) for plan CRUD, assignment, override, non-operator rejection, and the four config-cache tests — same Miniflare D1 + fake/`SELF.fetch` operator-auth pattern as B2 `control.test.ts` and I4 `entitle-grant.test.ts`. Cache I/O asserted with the A5 `D1Reader` spy (`vi.fn` / `readCount`, copied from `test/config-cache.test.ts` `makeReader`). Layers per delivery plan §3.12.10 G1 and §13.5. Suite joins CI permanently (§3.11).

**Target Platform**: `ai-platform/` Cloudflare Worker (D1 + `/control`). No `frontend/`, no `backend/`. Gateway remains additive, non-primary (§14).

**Project Type**: Band G commercial-surface slice, Worker-only. Not a new deployable. Nothing here is on the request path's latency budget (Delivery Plan §3.13).

**Performance Goals**: Operator-rare control mutations (no guard latency budget). Config cache: cold isolate exactly one D1 read per miss; warm isolate zero I/O (§4.3.2). No second Quota Durable Object round trip, no second D1 insert on the guard path, no second R2 object per request (§6.1, §7.5, §13.6). No per-request server-side state (§4.4, §9.7). Request path never sees a price (A15).

**Constraints**:
- Control plane remains separately authenticated by operator identity, not clinic identity (FR-001, FR-006). Non-operator rejection reuses B2 `401 unauthorized`; no new diagnostic code.
- Enroll still writes the plan name only and leaves entitlement `pending` with zeroed economics, including `credit_budget = 0` (FR-003, FR-004; Consumes B2 — do not rewrite `handleEnroll`).
- Every plan CRUD, assign-plan, and override mutation journals `control_audit` with operator identity (FR-005).
- Assign-plan reads the catalogue and copies monthly credit budget, request-count guard, `max_cost_class`, soft threshold, and capability set in one mutation; status → `active` (FR-014, FR-015). I4 grant/revoke path on `handleEntitle` is not reimplemented.
- Override of quota, budget, period bounds, or soft threshold is a distinct Entitlement-management mutation with a distinct `control_audit.action` (FR-016).
- Serve `plan` through the A5 cache as kind `"plans"` (forward-only `ConfigEntityKind` extension, same pattern as `"token_contracts"`). Do not rewrite TTL, miss semantics, ownership, or existing kinds (FR-017, FR-018). Do not cache `credit_price`.
- `credit_price` answers "what does the clinic pay per credit"; it is not the bundled token-rate artifact under `src/pricing/` (FR-019, FR-020). This slice does not activate versions or write `invoice`.
- No overage, debit, `quota_exhausted`, period close, invoice, or usage gauge (FR-021). Do not modify B4 `EntitlementSnapshot` / Quota DO (G2).
- Do not modify frozen Consumes contracts (A5 `contracts/config-cache.md`, B2 `contracts/control-plane.md`) — delivery plan §2.3.
- Plan `status` is persisted TEXT; this slice does not freeze a closed plan-status enum (spec Assumptions). Delete retains the row (full history, §7.3).

**Scale/Scope**: Two §4 components (§4.5 Control plane + §4.3.2 config cache — see Components Touched). Roughly: one additive migration + snapshot, one `plan.ts` CRUD module, entitle extension + override handler, config-cache kind + production reader branch, one workers integration test file, SQL assertions in the existing migrations harness, types/dispatch wiring. Twenty-one FRs. Thirteen named tests. Roughly 18–22 tasks — under the ~25-task ceiling (delivery plan §6.3 / plan stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — a
      handful of plan rows (A15 "stays small"); no marketplace, self-service enrollment,
      or payment-provider integration (constitution I; spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — additive D1 tables and `/control`
      mutations on the existing Worker; no new deployable.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated —
      G1 touches only `ai-platform/` (D1, Entitlement management, config cache). It does
      not touch `backend/` or `frontend/`. **§14 acknowledgement:** the Worker is an
      additive, non-primary component with no domain logic, no business data, and no
      write path into Supabase. Catalogue, `credit_price`, and the credit-budget column
      are platform D1 commercial records, not clinic business data (A15 constitution
      check).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — clinic Supabase
      integrity is untouched. Platform D1 integrity is held by A5 PK/NOT NULL columns,
      this slice's additive NOT NULL defaults, and `control_audit` with operator identity
      on every mutation (B2 pattern).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — control mutations use operator identity
      (B2 `OperatorAuth`); audited via `control_audit`; plan delete retains the row
      (full history). Operator scope is correctly above clinic-tenant scope for the
      control plane, as B2 established. No clinic table is written.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — plan CRUD
      and assignment are operator-invoked, not on the request hot path; pending
      entitlement stays closed until assignment; control-plane unavailability does not
      hard-lock clinic workflows (A15; constitution V; A11).

## Project Structure

### Documentation (this feature)

```text
specs/056-plan-catalogue/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify (authoritative)
├── data-model.md        # D1 entities this slice defines (`plan`, `credit_price`, entitlement columns)
├── contracts/
│   ├── plan-catalogue.md   # Plan table, CRUD / assign / override wire, cache kind `"plans"`
│   └── credit-price.md     # Versioned credit price-list table (activation is G4)
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`research.md` is **never** produced on this platform — the research is
`docs/architecture/ai-platform/01-ai-platform.md`.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — G1 row of the delivery plan (§3.13) and §4.5 / §7.3 /
  §4.3.2 / A15; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — additive `plan` / `credit_price` / `credit_budget` (and
  `max_cost_class`) migration; operator plan CRUD; plan-based entitle assignment;
  per-installation override; config-cache kind `"plans"`.
- **§3 Files to review** — only this slice's migration, `src/control/plan.ts`, entitle
  extension, config-cache kind/reader, this slice's workers test file, and the
  schema snapshot.
- **§4 Prerequisites** — Node/workers pool; `OPERATOR_*` bindings when exercising
  `SELF.fetch` control e2e (same as B2).
- **§5 Run the automated suite** — slice-only:
  `npx vitest run test/migrations.test.ts` and
  `npx vitest run --config vitest.workers.config.ts test/plan-catalogue.test.ts`;
  no full-suite `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — open migration + `plan.ts` + entitle copy-from-catalogue;
  grep `credit_budget` / `ConfigEntityKind` `"plans"`; confirm Consumes modules not rewritten.
- No **§7 Manual validation** — CI is the only verification path beyond the suite
  (control-plane behaviour is fully named in the thirteen tests).

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   ├── 20260731120000_platform_schema.sql                 # A5 — UNCHANGED (consumed)
│   ├── 20260821130000_entitlement_installation_unique.sql # prior — UNCHANGED
│   └── 20260911120000_plan_catalogue.sql                  # NEW — plan, credit_price,
│                                                          #   entitlement.credit_budget,
│                                                          #   entitlement.max_cost_class
├── schema.snap.sql                                        # MODIFIED — include new tables/columns
├── src/
│   ├── config-cache/
│   │   └── index.ts                                       # MODIFIED — ConfigEntityKind "plans"
│   │                                                      #   + createD1ConfigReader branch
│   └── control/
│       ├── plan.ts                                        # NEW — handlePlanCreate/Update/Delete
│       ├── entitle.ts                                     # MODIFIED — read catalogue on assign;
│       │                                                  #   handleOverride (distinct audit action)
│       ├── types.ts                                       # MODIFIED — PlanPayload, OverridePayload
│       ├── index.ts                                       # MODIFIED — isControlRoute + dispatch
│       ├── auth.ts                                        # UNCHANGED (Consumes B2)
│       ├── http.ts                                        # UNCHANGED (Consumes B2)
│       ├── audit.ts                                       # UNCHANGED (Consumes B2)
│       └── lifecycle.ts                                   # UNCHANGED (Consumes B2 — enroll)
├── vitest.workers.config.ts                               # MODIFIED — include plan-catalogue.test.ts
├── vitest.config.ts                                       # MODIFIED — exclude that file from Node pool
└── test/
    ├── migrations.test.ts                                 # MODIFIED — G1 named SQL tests + snapshot
    ├── entitle-grant.test.ts                              # MODIFIED — seed a catalogue plan so I4
    │                                                      #   entitle assertions stay green
    ├── plan-catalogue.test.ts                             # NEW — CRUD, assign, override, cache spies
    ├── config-cache.test.ts                               # UNCHANGED (Consumes A5 spy substrate)
    └── control.test.ts                                    # UNCHANGED (Consumes B2)
```

**Structure Decision**: Catalogue CRUD lands as a new sibling under `ai-platform/src/control/`
(same pattern as `token-contract.ts` / `kill-switch.ts`) and is wired only through the existing
barrel `dispatchControlRequest` / `isControlRoute`. Assignment extends I4's `entitle.ts` rather
than adding a parallel route (Delivery Plan §3.13). Override is a second handler in that
Entitlement-management module with a distinct `control_audit.action`. Cache kind `"plans"` is a
forward-only union extension; A5's `contracts/config-cache.md` is not edited. Enroll stays on
`lifecycle.ts` unchanged; `DEFAULT` on the new entitlement columns preserves pending non-null
shape.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How G1 binds to it |
| --- | --- | --- |
| **A5 — Context key vocabulary, D1 schema, and config cache** (forward-only additive D1 migrations, schema snapshot, in-isolate config cache: short TTL, D1 on miss, zero I/O when warm, one D1 read when cold; kinds already holding installations, keys, entitlements, grants, kill switches, active routing policy) | `ai-platform/migrations/20260731120000_platform_schema.sql`; `ai-platform/schema.snap.sql`; `ai-platform/test/migrations.test.ts` (`applyMigrations`, `schema_snapshot_matches`); `ai-platform/src/config-cache/index.ts` (`ConfigCache`, `loadConfig`, `D1Reader`, `ConfigCacheMissError`, `ConfigEntityKind`, `createD1ConfigReader`, `CACHE_TTL_MS`); spy substrate `ai-platform/test/config-cache.test.ts` (`makeReader`). Frozen artifacts: `specs/019-ai-context-keys-d1-config/contracts/config-cache.md`, `specs/019-ai-context-keys-d1-config/data-model.md`. | G1 **appends** one forward-only migration and updates the snapshot. It **extends** `ConfigEntityKind` with `"plans"` and adds a `createD1ConfigReader` branch (`SELECT` from `plan`). It does **not** rewrite existing entity shapes, TTL, one-read/zero-I/O, typed miss, or cache ownership. A5 contract files are not edited. |
| **B2 — Control-plane enrollment and installation lifecycle** (operator identity, not clinic identity; five lifecycle actions; enroll write set `installation` / `installation_key` / `entitlement` / `control_audit`; every mutation journals `control_audit`; enroll writes plan name only and leaves entitlement `pending` with zeroed economics) | `ai-platform/src/control/` — `auth.ts` (`createSecretOperatorAuth`), `http.ts` (`requireOperator`, `reject`, `ok`, `parseJsonBody`), `lifecycle.ts` (`handleEnroll` and the four other lifecycle handlers), `audit.ts` (`writeAudit`), barrel `index.ts` (`dispatchControlRequest` / `isControlRoute`); Worker `/control` dispatch in `worker.ts`. Frozen artifact: `specs/022-control-plane-enrollment/contracts/control-plane.md`. Spec/plan: `specs/022-control-plane-enrollment/`. | G1 **extends** the same operator-authenticated surface with plan CRUD, catalogue-reading assignment, and override. It does **not** rewrite enroll, suspend, resume, rotate, delete, or operator-auth. Non-operator rejection stays B2 `401 unauthorized`. `control_audit.action` vocabulary is extended (not rewritten) with plan CRUD / override values, same pattern J1/J3/I4 used. |

No consumed entry lacks an implementation. No consumed **contract** is rewritten (delivery plan §2.3). Stop condition 2 is not triggered.

I4 `handleEntitle` / `POST /control/installations/:id/entitle` is **not** a Consumes entry. Delivery Plan §3.13 names it as the entitle path G1 extends; spec Out of Scope forbids reimplementing I4 grant/revoke or self-heal. G1 binds to that handler as the assign-plan mutation (reads `plan`, copies economics, keeps I4 grant writes and B2 auth).

## Components Touched

| §4 component | What G1 changes | Behaviour added? |
| --- | --- | --- |
| §4.5 Control plane | Realises Entitlement management "maintain the plan catalogue", "Assign plan", "set quota and budget", and "set period bounds and soft threshold" as operator-authenticated, audited `/control` mutations. Does not rewrite Installation lifecycle (B2) or I4 grant/revoke / self-heal. | Yes — operators can CRUD plans, assign catalogue economics onto a pending entitlement, and record an explicit per-installation override. |
| §4.3.2 Identity and tenant resolution (config cache) | **Extended** — add config-cache kind `"plans"` and serve `entitlement` rows including `credit_budget` through the existing `"entitlements"` kind. TTL, miss, ownership, and existing kinds unchanged. | Yes — plans (and entitlements with the credit-budget column) follow the A5 warm/cold read pattern. |

**Written reason (more than one §4 component):** Delivery plan §3.13 row **G1** Canonical is `§4.5, §7.3, §4.3.2, A15` and Done when requires **both** (a) forward-only schema + audited plan CRUD / plan-based assignment and (b) serving plans and entitlements through the A5 config cache. §7.3 is the D1 shape written by the control plane; §4.3.2 is the cache that serves it. Neither half alone satisfies Done when. Stop condition 5 is satisfied by this reason; task count stays ~18–22.

No other §4 component is touched (Quota DO / B4 snapshot, Flutter, journal, providers, rate-limit, guard evaluation unchanged — G2/G3/G4).

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/migrations/20260911120000_plan_catalogue.sql` | Created | FR-007–FR-011 — `CREATE TABLE plan`, `CREATE TABLE credit_price`, `ALTER TABLE entitlement ADD COLUMN credit_budget INTEGER NOT NULL DEFAULT 0`, `ALTER TABLE entitlement ADD COLUMN max_cost_class TEXT NOT NULL DEFAULT ''`. |
| `ai-platform/schema.snap.sql` | Modified | FR-007 — snapshot includes `plan`, `credit_price`, and the entitlement credit-budget (and `max_cost_class`) column. |
| `ai-platform/src/control/plan.ts` | Created | FR-001, FR-002, FR-005, FR-006, FR-008, FR-013 — operator plan create/update/delete; journal `control_audit`; reject non-operator. |
| `ai-platform/src/control/entitle.ts` | Modified | FR-002, FR-005, FR-006, FR-011, FR-012, FR-014, FR-015, FR-016 — `handleEntitle` reads `plan` and copies economics in one mutation (`pending` → `active`); `handleOverride` journals a distinct action. I4 grant writes remain. |
| `ai-platform/src/control/types.ts` | Modified | FR-008, FR-015, FR-016 — `PlanPayload` / `OverridePayload` (and related) only. |
| `ai-platform/src/control/index.ts` | Modified | FR-001, FR-006 — extend `isControlRoute` / `dispatchControlRequest` for plan CRUD and override without altering lifecycle routes. |
| `ai-platform/src/config-cache/index.ts` | Modified | FR-017, FR-018 — extend `ConfigEntityKind` with `"plans"`; `createD1ConfigReader` SELECT from `plan`. Existing kinds, TTL, miss, ownership unchanged. |
| `ai-platform/test/migrations.test.ts` | Modified | SC-001 — named tests `migrations_apply_cleanly_empty_database` and `schema_snapshot_matches` asserting `plan`, `credit_price`, and `entitlement.credit_budget`. |
| `ai-platform/test/plan-catalogue.test.ts` | Created | SC-002–SC-005 — named integration tests for CRUD, assignment, override, non-operator, and four cache spies. |
| `ai-platform/test/entitle-grant.test.ts` | Modified | FR-014, FR-015 — seed a matching `plan` row so I4 entitle tests remain green after assignment reads the catalogue (do not rewrite I4 grant assertions). |
| `ai-platform/vitest.workers.config.ts` | Modified | SC-002–SC-005 — include `test/plan-catalogue.test.ts` in the workers pool. |
| `ai-platform/vitest.config.ts` | Modified | SC-002–SC-005 — exclude that workers file from the Node pool (same as `entitle-grant.test.ts`). |
| `specs/056-plan-catalogue/quickstart.md` | Created (implement phase) | — template-mandated review surface; sections named above. |

Every code file traces to an `FR-###`. No file is created for an unstated requirement. Consumed B2 lifecycle handlers and A5 cache mechanics stay unchanged aside from the listed extensions. `src/pricing/` (bundled token-rate artifact) is not touched (FR-020).

## Test Layout

The spec's `### Test plan` names thirteen tests (delivery plan §3.12.10 G1; §13.5 SQL / migration + integration). Place them as follows:

| Spec Test plan name | File | §13.5 layer | Asserts (FR / SC) |
| --- | --- | --- | --- |
| `migrations_apply_cleanly_empty_database` | `ai-platform/test/migrations.test.ts` | SQL / migration | FR-007 / SC-001 — forward-only migrations apply cleanly to an empty database (A5 `applyMigrations` harness). |
| `schema_snapshot_matches` | `ai-platform/test/migrations.test.ts` | SQL / migration | FR-007–FR-011 / SC-001 — snapshot matches and includes `plan`, `credit_price`, and `entitlement.credit_budget`. |
| `plan_create_audit` | `ai-platform/test/plan-catalogue.test.ts` | Integration | FR-005, FR-008, FR-013 / SC-002 — create writes `plan` + `control_audit` with operator identity. |
| `plan_update_audit` | `ai-platform/test/plan-catalogue.test.ts` | Integration | FR-005, FR-013 / SC-002 — update journals `control_audit` with operator identity. |
| `plan_delete_audit` | `ai-platform/test/plan-catalogue.test.ts` | Integration | FR-005, FR-013 / SC-002 — delete journals `control_audit` with operator identity (row retained). |
| `plan_crud_non_operator_rejected` | `ai-platform/test/plan-catalogue.test.ts` | Integration | FR-006 / SC-002 — non-operator rejected on every plan CRUD mutation; no catalogue or audit write (B2 `401 unauthorized`). |
| `assign_plan_populates_economics_one_audited_mutation` | `ai-platform/test/plan-catalogue.test.ts` | Integration | FR-011, FR-014, FR-015 / SC-003 — assign copies credit budget, request-count guard, `max_cost_class`, soft threshold, capability set in one mutation; status `active`; `control_audit` with operator identity. |
| `per_installation_override_recorded_as_such` | `ai-platform/test/plan-catalogue.test.ts` | Integration | FR-016 / SC-004 — override journals a distinct `control_audit.action` from assign-plan. |
| `assignment_non_operator_rejected` | `ai-platform/test/plan-catalogue.test.ts` | Integration | FR-006 / SC-002 — non-operator rejected on assign-plan and override; no entitlement or audit write. |
| `config_cache_plan_cold_one_d1_read` | `ai-platform/test/plan-catalogue.test.ts` | Integration | FR-017 / SC-005 — serving a plan from a cold isolate: exactly one `D1Reader.read` (A5 spy). |
| `config_cache_plan_warm_zero_io` | `ai-platform/test/plan-catalogue.test.ts` | Integration | FR-017 / SC-005 — serving a plan from a warm isolate: zero I/O. |
| `config_cache_entitlement_cold_one_d1_read` | `ai-platform/test/plan-catalogue.test.ts` | Integration | FR-010, FR-017 / SC-005 — serving an entitlement including `credit_budget` from a cold isolate: exactly one D1 read. |
| `config_cache_entitlement_warm_zero_io` | `ai-platform/test/plan-catalogue.test.ts` | Integration | FR-017 / SC-005 — serving an entitlement from a warm isolate: zero I/O. |

Every named test from the spec is placeable in §13.5. No named test is orphaned.

## Sequencing

1. **Tests first (or alongside)** — add the two G1-named describes in `migrations.test.ts` and the failing `plan-catalogue.test.ts` cases (CRUD, assign, override, cache spies) against missing tables / handlers (never after implementation).
2. **Migration** — `20260911120000_plan_catalogue.sql` + update `schema.snap.sql`; turn SQL tests green (FR-007–FR-011).
3. **Config-cache kind** — extend `ConfigEntityKind` with `"plans"` and the production reader branch; keep TTL / miss / existing kinds untouched (FR-017, FR-018).
4. **Plan CRUD** — `plan.ts` + `PlanPayload` types; dispatch routes; `control_audit` actions `plan_create` / `plan_update` / `plan_delete` (FR-001, FR-005, FR-013).
5. **Assign-plan** — extend `handleEntitle` to `SELECT` the catalogue row (by enrolled `entitlement.plan`, or body `plan` then that name), copy economics in the same D1 batch as I4's grant + audit writes, set `status = 'active'` (FR-014, FR-015). Seed `plan` in `entitle-grant.test.ts`.
6. **Override** — `handleOverride` on `POST /control/installations/{id}/override`; distinct `control_audit.action`; before/after pointer records the change (FR-016).
7. **Turn integration tests green** — including non-operator cases via B2 `requireOperator` (FR-006) and the four cache spies (A5 `D1Reader` `readCount`).
8. **Verification** — slice-only vitest commands above; confirm `lifecycle.ts` / A5 cache contract file / `src/pricing/` untouched; confirm no Quota DO field changes.
9. **Documentation** — write `quickstart.md` per sections above.

## Complexity Tracking

> No constitution violations requiring justification. Empty by design.
