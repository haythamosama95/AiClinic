# Implementation Plan: Token contract rotation with overlapping acceptance (J4)

**Branch**: `ai/051-j4-token-contract-rotation` | **Date**: 2026-08-03 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/051-token-contract-rotation/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

J4 adds deferred band-J Token contract rotation: a platform-global D1 `token_contract`
accepted-`ver` set (exactly one when stable, at most two mid-rotation), control-plane
begin-rotation / retire as its only writers (each writing `control_audit`), identity-stage
overlapping acceptance of every `ver` in that set with retired/unknown `ver` refused as existing
`unauthenticated`, and clinic-side single mint from `ai.aat.ver` with every §5.6 claim and no
re-enrollment. It sits in band J after B1 and B3 (`Needs: B1, B3`); build when the token contract
needs its first change (delivery plan §3.9 row J4; DP-5).

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`), `target: ES2022`,
strict, `@cloudflare/workers-types` — matching B3/B2; PostgreSQL 15 (`supabase/postgres:15.8.1.085`)
PL/pgSQL for clinic-side mint SQL tests — matching B1.

**Primary Dependencies**: existing `ai-platform/src/identity/` (B3 — `TokenVerifier`,
`EnrolledKeyVerifier`, `VerifyResult`, `Principal`); `ai-platform/src/config-cache/` (A5 —
`ConfigCache`, `loadConfig`, `D1Reader`, `ConfigEntityKind`); `ai-platform/src/control/` (B2 —
`OperatorAuth`, `dispatchControlRequest`, `control_audit` insert pattern); `ai-platform/src/errors.ts`
(A2 — existing `unauthenticated`); B1 clinic issuer
(`auth_internal.issue_ai_token`, `ai_internal.app_settings` key `ai.aat.ver`, frozen
`specs/021-installation-keystore-aat-issuer/contracts/aat-token.md`). No new runtime dependency; no
schema-validation or HTTP-framework library (R-20).

**Storage**: Platform D1 — **new** `token_contract` table (one row per `ver`; accepted set =
rows with no `retired_at`; no `retire_after` / TTL) plus `control_audit` writes on both transitions
(B2 Freezes). Clinic Supabase — existing `ai_internal.app_settings` row `ai.aat.ver` (B1 already
seeds and the issuer already reads it); J4 advances that setting as an operator clinic-deployment
action and does **not** add a platform write path into Supabase. No R2, no Quota DO.

**Testing**: Unit + SQL (delivery plan §3.11.8 row J4; §13.5).
- Unit: `npx vitest run test/token-contract-rotation.test.ts` (Node pool) — overlapping acceptance,
  retired/unknown → `unauthenticated`, request-path never writes `token_contract`.
- D1 SQL (workers): `npx vitest run --config vitest.workers.config.ts test/token-contract-control.test.ts`
  — accepted-set cardinality, begin-rotation / retire + `control_audit`, no-re-enrollment half on
  the platform side.
- Clinic SQL: `psql -f backend/tests/ai_token_contract_rotation.sql` (wired into
  `backend/tests/run_ai_platform_trust_tests.sh`) — new-contract claim completeness, single mint
  from `ai.aat.ver`, no-re-enrollment mint half.
  Workers file registered in **both** harness configs (`vitest.workers.config.ts` `include` and
  `vitest.config.ts` `exclude`) so default `npx vitest run` stays green (B2/C1/J1 precedent).
  Slice-only; suite joins CI permanently (§3.10).

**Target Platform**: `ai-platform/` Cloudflare Worker (D1 `token_contract`, control-plane writers,
identity accepted-`ver` check) and clinic `backend/` Supabase (operator-advanced `ai.aat.ver` mint
verification). No Flutter surface.

**Project Type**: Additive gateway behaviour plus clinic-side mint verification — gateway remains
non-primary (§14 acknowledgement); clinic issuer stays the existing B1 `SECURITY DEFINER` RPC.

**Performance Goals**: Accepted-`ver` check is a config-cache consult (warm isolate: zero D1 I/O;
cold: one same-region D1 read per miss) — no second Quota DO round trip, no second R2 object, no
per-request server-side state (§4.4, §7.5, §9.7, §13.6). Control mutations are operator-rare (off
request-path budgets).

**Constraints**:
- Accepted set: exactly one `ver` when stable, at most two mid-rotation (FR-002).
- No `retire_after`, no TTL, no auto-retire; "during"/"after" are set membership (FR-004; §5.7).
- Begin-rotation and retire are the only writers; request path never writes `token_contract`
  (FR-005).
- Refusal of a `ver` outside the set is existing `unauthenticated` — **no new taxonomy code**
  (FR-010).
- Issuer mints exactly one `ver` from `ai.aat.ver`; platform never reads or writes that setting
  (FR-011, FR-012).
- Rotation does not require re-enrollment; `iss`+`kid` still select the enrolled key (FR-015);
  `alg: EdDSA` stays non-negotiable; deliberate omissions preserved (FR-016, FR-017).
- No rewrite of B1 keystore / issuer / claim set / scopes derivation, or B3 signature / audience /
  expiry / skew / rate-limit / entitlement / kill-switch (delivery plan §2.3).
- No §9.14 mechanism; no dual-mint; no timed retirement (R-20; delivery plan §6.4).

**Scale/Scope**: Two §4 components modified (§4.3.2 Identity, §4.5 Control plane) plus clinic-side
mint verification against the existing §4.2 issuer — see **Components Touched** for the written
reason. One D1 migration, config-cache kind extension, identity + control extensions, two Worker
test files, one clinic SQL suite, one data-model, one contract, one named quickstart. Roughly
16–20 tasks (under the ~25 ceiling of delivery plan §6.3 / plan stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — overlapping
      `ver` acceptance lets clinics advance minting at their own pace without fleet re-enrollment
      (constitution I; §5.6; §5.7; spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — one new D1 table, two control mutations,
      one identity check through the existing config cache, and an existing clinic settings row;
      no new service.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — clinic mint
      stays in `backend/` (B1 issuer + `ai.aat.ver`); accepted-`ver` authority and control writers
      live in `ai-platform/`; no Flutter AI surface; gateway has no write path into Supabase.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — clinic mint and
      `ai.aat.ver` remain behind B1's RLS-locked `ai_internal` schema and `SECURITY DEFINER`
      issuer; platform D1 `token_contract` is written only by operator-authenticated control
      mutations (not the request path).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — AATs stay EdDSA-signed with RBAC-derived `scopes`;
      both rotation edges write `control_audit` with operator identity; retired/unknown `ver`
      refuse as `unauthenticated`; append-only `token_contract` history (no soft-delete of clinic
      data).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — bad/`ver`-rejected
      tokens degrade to AI-unavailable; clinical work continues without the gateway
      (constitution V; §14).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no
domain logic, no business data, and no write path into Supabase. J4 only adds platform D1
`token_contract` + control audit writers and an identity-stage accepted-`ver` consult; advancing
`ai.aat.ver` stays an operator action on the clinic deployment.

## Project Structure

### Documentation (this feature)

```text
specs/051-token-contract-rotation/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify output (authoritative)
├── data-model.md        # D1 `token_contract` entity (this slice defines it)
├── contracts/
│   └── token-contract-rotation.md  # Freezes: accepted-ver set, control writers,
│                                   # unauthenticated refusal, ai.aat.ver mint
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` **is** produced — J4 defines the D1 entity `token_contract` (spec Key Entities;
§7.3). A5's shipped schema omitted this table (A5 presence cases listed eleven entities before the
§7.3 `token_contract` amendment); J4 creates it forward-only and does **not** rewrite A5's
`data-model.md` (delivery plan §2.3).

`research.md` is **never** produced on this platform — the research is
`docs/architecture/17-ai-platform.md`.

`contracts/` **is** produced — Freezes entries have wire / table / mutation / error shapes
(accepted-`ver` set, begin-rotation / retire control routes and `control_audit.action` values,
`unauthenticated` refusal path, `ai.aat.ver` single-mint rule) that later slices' **Consumes** must
bind to.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — J4 row of the delivery plan (§3.9) and Implements (§5.7, §5.6,
  §4.5, §7.3); what the spec delivered; what the plan scoped.
- **§2 What was implemented** — D1 `token_contract` migration + seed; begin-rotation / retire;
  identity accepted-`ver` check; clinic SQL coverage for `ai.aat.ver` single mint.
- **§3 Files to review** — this slice's migration, `src/identity/` / `src/control/` /
  `src/config-cache/` diffs, Worker + clinic test files, `data-model.md`,
  `contracts/token-contract-rotation.md`.
- **§4 Prerequisites** — Miniflare D1 workers pool for control SQL tests; local Supabase for
  clinic SQL; one-time `npm install` in `ai-platform/`.
- **§5 Run the automated suite** — slice-only Unit, workers SQL, and clinic SQL commands above.
- **§6 Inspect the changes** — grep `token_contract` / begin-rotation / retire; confirm no new
  taxonomy code; confirm issuer still reads `ai.aat.ver`.
- No **§7 Manual validation** — CI is the only verification path beyond the suite.

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   ├── 20260731120000_platform_schema.sql             # A5 — unchanged (consumed)
│   ├── 20260802100000_capability_grant_lifecycle.sql  # J1 — unchanged
│   ├── 20260803100000_routing_policy_canary.sql       # J3 — unchanged
│   └── 20260803120000_token_contract.sql              # NEW — token_contract + seed ver '1'
├── schema.snap.sql                                    # MODIFIED — reflect token_contract
├── src/
│   ├── identity/
│   │   └── index.ts                                   # MODIFIED — accepted-ver check via
│   │                                                  #   config cache; refuse as
│   │                                                  #   unauthenticated (FR-001, FR-009,
│   │                                                  #   FR-010)
│   ├── config-cache/
│   │   └── index.ts                                   # MODIFIED — extend ConfigEntityKind
│   │                                                  #   with "token_contracts" (FR-009)
│   ├── control/
│   │   ├── token-contract.ts                          # NEW — begin-rotation / retire
│   │   │                                              #   handlers + FR-002 guards +
│   │   │                                              #   control_audit (FR-005..FR-008)
│   │   └── index.ts                                   # MODIFIED — re-export handlers +
│   │                                                  #   dispatchControlRequest routes
│   ├── errors.ts                                      # UNCHANGED — reuse unauthenticated
│   └── worker.ts                                      # MODIFIED — /control token-contract
│                                                      #   routes
├── test/
│   ├── token-contract-rotation.test.ts                # NEW — Unit tests 1–3, 7, Unit half of 10
│   └── token-contract-control.test.ts                 # NEW — D1 SQL tests 4–6, SQL half of 10
├── vitest.workers.config.ts                           # MODIFIED — include control test file
└── vitest.config.ts                                   # MODIFIED — include unit file; exclude
                                                       #   workers control file from Node pool

backend/
├── supabase/migrations/
│   ├── 20260801120000_ai_keystore_schema.sql          # B1 — unchanged (ai.aat.ver seed)
│   └── 20260801120200_ai_token_issuer_rpc.sql         # B1 — unchanged (reads ai.aat.ver)
└── tests/
    ├── ai_token_contract_rotation.sql                 # NEW — SQL tests 8–9, SQL half of 10
    └── run_ai_platform_trust_tests.sh                 # MODIFIED — register the new SQL file
```

**Structure Decision**: Extend B3's `src/identity/` and B2's `src/control/` in place (same
`index.ts` pattern as J1). Add config-cache kind `"token_contracts"` as a forward-only extension of
A5's kind union (same pattern as `"active_routing_policy"`) without rewriting A5's
`contracts/config-cache.md`. Clinic mint stays on B1's issuer; J4 adds SQL coverage that advances
`ai.aat.ver` and asserts single-`ver` claim-complete mint — no issuer rewrite. One workers-pool
test file for D1 SQL assertions; one Node-pool unit file for verifier behaviour; one clinic SQL
suite for minting side.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How J4 binds to it |
| --- | --- | --- |
| **B1** — installation keystore; AAT issuer (`alg: EdDSA` compact JWS, every §5.6 claim including `ver`); `scopes` derived server-side from RBAC; key-set rotation without re-enrollment | `backend/supabase/migrations/20260801120000_ai_keystore_schema.sql` (`ai_internal.app_settings` including `ai.aat.ver`); `20260801120100_ai_installation_keypair_routines.sql`; `20260801120200_ai_token_issuer_rpc.sql` (`auth_internal.issue_ai_token` already mints `ver` from `ai.aat.ver`); frozen artifact `specs/021-installation-keystore-aat-issuer/contracts/aat-token.md`. | J4 **advances** minting `ver` by operator update of `ai.aat.ver` and **verifies** single-`ver` claim-complete mint under the new value (FR-011..FR-017). It does **not** redefine the keystore, issuer RPC, EdDSA signing, claim set, or `scopes` derivation. B1 contract file is not edited. |
| **B3** — token verifier port (WebCrypto `Ed25519`, `alg` pinned to `EdDSA`); audience / expiry / skew; immutable principal | `ai-platform/src/identity/index.ts` — `TokenVerifier`, `EnrolledKeyVerifier`, `VerifyContext`, `VerifyResult`, `Principal`; frozen artifact `specs/023-guard-stages/contracts/token-verifier.md` (explicitly names J4 as an allowed extender for overlapping `ver` acceptance). Config cache: `ai-platform/src/config-cache/index.ts` (`loadConfig`, `ConfigCache`) as B3 already uses for installations / keys. | J4 **extends** `EnrolledKeyVerifier` with an accepted-`ver` consult against D1 `token_contract` through kind `"token_contracts"` (FR-001, FR-009, FR-010). It does **not** redefine signature, audience, expiry, skew, rate limiting, entitlement, or kill-switch evaluation. B3 contract file is not edited. |

No consumed entry lacks an implementation. None of the frozen Consumes contracts is rewritten
(delivery plan §2.3). Control-plane `OperatorAuth` / `control_audit` row shape (B2) and A2
`unauthenticated` are used as infrastructure already present on the integration line; they are not
listed in the spec's **Consumes** and are not modified beyond extending B2's allowed `action`
vocabulary with `token_contract_begin_rotation` / `token_contract_retire` (same extension pattern
J1/J3 used).

## Components Touched

| §4 component | What J4 changes | Behaviour added? |
| --- | --- | --- |
| §4.3.2 Identity and tenant resolution | **Extended** — after existing signature/audience/expiry/skew checks, consult accepted-`ver` set via config cache; accept every member; refuse others as `unauthenticated`. | Yes — §5.6 accepting side deferred to J4. |
| §4.5 Control plane | **Extended** — Token contract rotation: begin-rotation (insert new `ver`) and retire (stamp `retired_at`); both write `control_audit`. | Yes — §4.5 Token contract rotation row enacted here. |
| §4.2 Clinic backend (AI token issuer / settings) | **Not rewritten** — B1 issuer already reads `ai.aat.ver`; J4 adds SQL tests that advance the setting and assert single-`ver` claim-complete mint. No new clinic migration. | Behaviour verified (FR-011..FR-014), issuer code unchanged. |

**Written reason for touching more than one §4 component:** J4's Done when and Freezes require both
halves of one recipe plus mint verification: (1) control-plane writers that open/close the
accepted-`ver` set and journal `control_audit`, and (2) identity-stage verification that accepts
every `ver` in that set and refuses the rest as `unauthenticated`. Delivery plan §3.9 Needs are
exactly `B1, B3`; §5.6 names minting side and accepting side as two sides of one `ver` timeline.
Neither identity nor control alone satisfies overlapping acceptance; clinic SQL proves the minting
side without rewriting B1. Stop condition 5 is satisfied by this reason; task count stays ~16–20.

No other §4 component is touched (Quota DO / R2 / journal / Flutter / providers / rate-limit /
entitlement unchanged).

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/migrations/20260803120000_token_contract.sql` | Created | FR-002, FR-003, FR-004 — `CREATE TABLE token_contract (ver, added_at, retired_at, changed_by)` with no `retire_after`; seed one accepted row `ver = '1'` (matches B1 default `ai.aat.ver`) so the stable set has exactly one member. |
| `ai-platform/schema.snap.sql` | Modified | FR-003 — snapshot matches post-migration `token_contract` shape. |
| `ai-platform/src/config-cache/index.ts` | Modified | FR-009 — extend `ConfigEntityKind` with `"token_contracts"` (forward-only; A5 contract file untouched). |
| `ai-platform/src/identity/index.ts` | Modified | FR-001, FR-009, FR-010 — `EnrolledKeyVerifier` loads accepted `ver` via `loadConfig(..., "token_contracts", payload.ver)`; miss / retired → `{ ok: false, code: "unauthenticated" }`; no new taxonomy code; signature/audience/expiry/skew path unchanged. |
| `ai-platform/src/control/token-contract.ts` | Created | FR-005, FR-006, FR-007, FR-008 — `handleTokenContractBeginRotation` / `handleTokenContractRetire`; atomic at-most-two insert / return-to-one retire (FR-002); write `control_audit`. |
| `ai-platform/src/control/index.ts` | Modified | FR-008 — re-export handlers; `dispatchControlRequest` routes for `/control/token-contract/...`. |
| `ai-platform/src/worker.ts` | Modified | FR-008 — dispatch new `/control/token-contract/...` paths (same `/control` boundary B2 froze). |
| `ai-platform/test/token-contract-rotation.test.ts` | Created | Tests 1–3, 7, Unit half of 10 (SC-001, SC-002, SC-005, SC-008); static non-writer scan. |
| `ai-platform/test/token-contract-control.test.ts` | Created | Tests 4–6, SQL/D1 half of 10 (SC-003, SC-004, SC-008); writer-enforcement + retire error + operator-auth + `createD1ConfigReader` identity path. |
| `ai-platform/vitest.config.ts` | Modified | — include unit file; exclude workers control file from Node pool. |
| `ai-platform/vitest.workers.config.ts` | Modified | — include `test/token-contract-control.test.ts`. |
| `backend/tests/ai_token_contract_rotation.sql` | Created | Tests 8–9, SQL half of 10 (SC-006, SC-007, SC-008) — advance `ai.aat.ver`, mint, assert every §5.6 claim and single `ver`; same enrolled installation without re-enrollment. |
| `backend/tests/run_ai_platform_trust_tests.sh` | Modified | — register `ai_token_contract_rotation.sql` in the trust suite. |
| `specs/051-token-contract-rotation/data-model.md` | Created | FR-002, FR-003, FR-004 — D1 `token_contract` entity binding surface. |
| `specs/051-token-contract-rotation/contracts/token-contract-rotation.md` | Created | Freezes — accepted-`ver` set, control writers, `unauthenticated` refusal, `ai.aat.ver` single mint (FR-001..FR-017). |
| `specs/051-token-contract-rotation/quickstart.md` | Created (implement phase) | — template-mandated review surface; sections named above. Not traced to an FR. |

Every code/contract file traces to an `FR-###`. Consumed modules' frozen contracts
(`aat-token.md`, `token-verifier.md`, `control-plane.md`, A5 `config-cache.md` / `data-model.md`)
are **not** modified. No untraced file. No `research.md`.

## Test Layout

The spec's Test plan names ten tests at layers **Unit** and **SQL** (delivery plan §3.11.8 J4).
Mapped onto §13.5: Unit cases exercise the identity guard path (Pipeline / guard-rejection
family, same placement B3 used for Unit identity); clinic SQL maps to §13.5 Contract tests (B1
precedent); D1 SQL assertions run under the workers Pipeline harness (J1/B2 precedent for
control-plane + D1 state).

| Spec Test plan name | Test id | Spec layer | §13.5 placement | File / config | Asserts (FR / SC) |
| --- | --- | --- | --- | --- | --- |
| `both_ver_values_verify_during_rotation_window` | T-J4-01 | Unit | Unit (guard) | `test/token-contract-rotation.test.ts` / `vitest.config.ts` | FR-001, FR-002 / SC-001 — accepted set has two members → both `ver` values verify. |
| `retired_ver_refused_as_unauthenticated` | T-J4-02 | Unit | Unit (guard) | same | FR-010 / SC-002 — after retire, prior `ver` → `{ ok: false, code: "unauthenticated" }`; taxonomy unchanged. |
| `unknown_ver_refused_as_unauthenticated` | T-J4-03 | Unit | Unit (guard) | same | FR-010 / SC-002 — never-accepted `ver` → same `unauthenticated` path. |
| `accepted_set_is_one_when_stable_and_two_mid_rotation` | T-J4-04 | SQL | Pipeline (D1) | `test/token-contract-control.test.ts` / `vitest.workers.config.ts` | FR-002, FR-003 / SC-003 — `WHERE retired_at IS NULL` count is 1 stable / 2 mid-rotation. |
| `begin_rotation_adds_ver_and_keeps_prior` | T-J4-05 | SQL | Pipeline (D1) | same | FR-006, FR-008 / SC-004 — insert new `ver`, prior remains accepted, `control_audit` action `token_contract_begin_rotation`. |
| `retire_stamps_retired_at_and_returns_set_to_one` | T-J4-06 | SQL | Pipeline (D1) | same | FR-007, FR-008 / SC-004 — stamp `retired_at`, accepted count → 1, `control_audit` action `token_contract_retire`. |
| `request_path_never_writes_token_contract` | T-J4-07 | Unit | Unit (spy) | `test/token-contract-rotation.test.ts` / `vitest.config.ts` | FR-004, FR-005 / SC-005 — identity (and request-path) verification performs no `token_contract` write; no auto-retire. |
| `new_contract_token_carries_every_claim` | T-J4-08 | SQL | Contract (clinic) | `backend/tests/ai_token_contract_rotation.sql` | FR-013, FR-016, FR-017 / SC-006 — after advancing `ai.aat.ver`, mint populates every §5.6 claim. |
| `issuer_mints_single_ver_from_ai_aat_ver` | T-J4-09 | SQL | Contract (clinic) | same | FR-011, FR-012, FR-014 / SC-007 — exactly one `ver` from `ai.aat.ver`; no dual-mint; `scopes` still RBAC-derived. |
| `rotation_requires_no_re_enrollment` | T-J4-10 | Unit + SQL | Unit + Pipeline + Contract | unit file + workers file + clinic SQL | FR-015 / SC-008 — same enrolled `iss`+`kid` still mint and verify after contract rotation; no re-enrollment step. |

Coverage from §3.10: the only error code this slice's `ver`-refusal path emits is existing
`unauthenticated` (T-J4-02, T-J4-03); no new code. Branches: two-member overlap vs post-retire vs
never-accepted; begin-rotation vs retire; request-path non-writer; single mint from settings.
Inherited prohibitions (no second Quota DO / R2; no per-request state; no §9.14) are constraints
on this slice's design and are not re-asserted as separate cases beyond T-J4-07's no-write spy.

Every named test places in a §13.5 layer — stop condition 3 not triggered.

## Sequencing

Tests land first or alongside implementation, never after (delivery plan §2.2):

1. **Migration (FR-002..FR-004)** — `token_contract` DDL + seed `ver = '1'` + `schema.snap.sql`
   update so D1 accepts the entity.
2. **Config-cache kind + identity accepted-`ver` check (FR-001, FR-009, FR-010)** — T-J4-01 /
   T-J4-02 / T-J4-03 / T-J4-07 against a seeded / spy cache (before or with control handlers).
3. **Control-plane begin-rotation / retire (FR-005..FR-008)** — handlers + routes; T-J4-04 /
   T-J4-05 / T-J4-06 driven through the mutation path against real Miniflare D1; enforce
   at-most-two and return-to-one.
4. **Clinic SQL (FR-011..FR-017)** — T-J4-08 / T-J4-09 / T-J4-10 mint half against local
   Supabase (advance `ai.aat.ver`, mint, assert claims; no re-enrollment).
5. **No-re-enrollment platform half (FR-015)** — T-J4-10 Unit/D1: same enrolled key verifies
   tokens under both accepted `ver` values.
6. **Contract + data-model** — `contracts/token-contract-rotation.md` and `data-model.md`
   written alongside the module / migration surface (already present at plan time; implement
   keeps them accurate).
7. **Documentation** — `quickstart.md` last, during the implement-phase Documentation task,
   after the slice's tests pass.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. Every checkbox is ticked;
> the §14 gateway acknowledgement is recorded in Constitution Check, not here.
