# Implementation Plan: Installation keystore and AAT issuer

**Branch**: `021-b1-installation-keystore-aat-issuer` | **Date**: 2026-07-31 | **Spec**: [`specs/021-installation-keystore-aat-issuer/spec.md`](spec.md)

**Input**: Feature specification from `specs/021-installation-keystore-aat-issuer/spec.md`

## Summary

B1 establishes the clinic-side half of the trust bootstrap: an installation id and an Ed25519
private signing key held in a restricted `ai_internal` schema, plus a `SECURITY DEFINER` AAT
issuer RPC in `auth_internal` that verifies the caller's session, derives every §5.6 claim
(including `scopes`, from RBAC) server-side, mints a short-lived `alg: EdDSA` JWS, records the
issuance, and rate-limits itself. It sits at the head of band B (`Needs` empty); B3 and B4
consume the AAT contract it freezes.

> **Note on superseded clarifications.** The `## Clarifications` session in `spec.md` recorded
> Q1 as "ES256" and Q3 fixtures as "ES256" because, at clarify time, the cited sections named no
> signing mechanism. `docs/architecture/17-ai-platform.md` has since added **§4.2.1 The
> clinic-side signing mechanism**, which fixes `pgsodium` Ed25519 / `alg: EdDSA` as the only
> compliant mechanism and §5.6 makes `alg` non-negotiable. Per the delivery plan rule that the
> architecture wins over stale choices, this plan follows **§4.2.1 (EdDSA)**, not the ES256
> clarification bullets. Q2 (keystore in a new `ai_internal` schema; issuer in `auth_internal`
> as `SECURITY DEFINER`) and the SQL/RLS-only test construction of Q3 hold unchanged — the
> verifier uses `pgsodium.crypto_sign_verify_detached` as §4.2.1 names for the clinic-side
> self-test.

## Technical Context

**Language/Version**: PostgreSQL 15 (`supabase/postgres:15.8.1.085`), PL/pgSQL; SQL migrations and SQL/RLS test scripts.

**Primary Dependencies**: Supabase (GoTrue, PostgREST), the existing `auth_internal` `SECURITY DEFINER` pattern (F4), the existing `public.staff_members` / `public.staff_branch_assignments` / `public.organizations` / `public.branches` / `public.roles_permissions` RBAC tables, and the **`pgsodium`** extension (shipped in the image, available-but-not-enabled — F8; §4.2.1). `pgjwt` is HMAC-only and is **not** used (§4.2.1). `supabase_vault` is installed and may wrap the secret key (§4.2.1); this plan stores the secret key in the restricted `ai_internal` schema per the §4.2 "restricted schema" requirement and does not require Vault.

**Storage**: Clinic Supabase PostgreSQL only. New restricted schema `ai_internal` (keystore + issuance ledger); issuer and keypair routines in `auth_internal`. **No D1, no R2, no Durable Object, no Worker code** — B1 touches `backend/` only.

**Testing**: SQL/RLS scripts run via `psql` against the local Supabase stack (the layer named in delivery plan §3.11.2 row B1 and §13.5 "Contract tests … CI, on every change"). New runner `backend/tests/run_ai_platform_trust_tests.sh` invokes the two B1 SQL suites; it is added to `backend/tests/run_auth_backend_tests.sh`'s `sql_tests` array so CI runs it with the existing auth suite. Slice-only: `psql -f backend/tests/ai_keystore_rls.sql && psql -f backend/tests/ai_token_issuer.sql` (no prior AI-platform slice has backend tests; bands A are Worker-side).

**Target Platform**: Self-hosted Supabase on a clinic PC (Tier 1, F1). The platform (gateway) is not built by this slice.

**Project Type**: Additive clinic-backend migrations + RPCs, following the established `public` wrapper → `auth_internal` `SECURITY DEFINER` idiom (F4).

**Performance Goals**: None named by the cited sections for B1. The issuer is a request-scoped RPC; no streaming, no I/O budget to preserve (the §6.1/§7.5/§13.6 budgets are guard budgets that belong to B3/B4, explicitly out of scope).

**Constraints**: Signing mechanism forced to `pgsodium` Ed25519 / `alg: EdDSA` (§4.2.1; §5.6 non-negotiable `alg`); `scopes` derived server-side from RBAC and never client-supplied (§5.6); keystore unreadable by `anon`/`authenticated` (§4.2); rotation additive (§4.2, §8.1); AAT lifetime "minutes" and issuer rate-limit thresholds are configuration values, not architecturally fixed numbers (§5.6, §4.2) — this plan wires them as `ai_internal.app_settings`-style config keys with defaults, inventing no contract a later slice binds to.

**Scale/Scope**: One installation per clinic, a few signing keys per installation, one issuance ledger row per mint. Clinic-scale (constitution I).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — B1 folds AI
      trust into the existing per-clinic Supabase/GoTrue identity (F2); no new identity provider,
      no enterprise infrastructure (§14 row I).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — B1 is a set of Postgres migrations and
      `SECURITY DEFINER` RPCs in the existing clinic backend. No new deployable is introduced by
      this slice (the gateway itself is a separate, already-acknowledged deployable; B1 adds
      nothing to `ai-platform/`).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — B1 touches
      `backend/` (Supabase/PostgreSQL) only. No Flutter, no Worker. The §14 acknowledgement
      ("the Worker is an additive, non-primary component with no domain logic, no business data,
      and no write path into Supabase, always optional") applies to the platform; this slice is
      the clinic-side counterpart that lets the platform verify clinic tokens in one direction
      only (§8.1), and it writes no domain logic and no business data beyond the two AI-shaped
      facts the §4.2 boundary note permits.
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — the keystore is RLS-locked
      to `anon`/`authenticated` deny; the issuer and keypair routines are `SECURITY DEFINER` in
      `auth_internal` with `public` `SECURITY DEFINER` wrappers, matching F4; `scopes` derivation is a
      server-side RBAC read, not client input (constitution III, IV).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — the issuer requires `auth.uid()` (§4.2 "Verify the
      caller's session"); issuance is recorded (§4.2; constitution IV auditability); the keystore
      tables follow the repo's shared schema conventions (id, timestamps, `is_deleted`).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — B1 mints a token only;
      it performs no AI action, writes no clinical record, and does not gate any clinical workflow.
      AAT issuance failure degrades to "AI unavailable", which is strictly additive (§14 row I).

## Project Structure

### Documentation (this feature)

```text
specs/021-installation-keystore-aat-issuer/
├── spec.md              # produced by /ai-platform-specify
├── plan.md              # this file
├── quickstart.md        # produced during the Documentation task after implementation
├── contracts/
│   └── aat-token.md     # the frozen AAT JWS contract (Freezes → wire/token shape)
└── tasks.md             # produced by /ai-platform-tasks (NOT this phase)
```

`data-model.md` is **not** produced: B1 defines clinic-side Supabase entities, not D1 entities
(the platform's store). `research.md` is **never** produced — the research is
`docs/architecture/17-ai-platform.md` (delivery plan §6).

`contracts/aat-token.md` is required because a **Freezes** entry has a wire shape: the AAT is a
JWS whose header carries `alg: EdDSA` + `kid` (§5.6, §4.2.1) and whose payload is the §5.6 claim
set. A later slice's **Consumes** (B3's token verifier, B4's `jti` freshness) must bind to a
frozen artifact, not to prose. It is written during implementation and pinned by the T07/T12
contract tests.

The quickstart is written during the Documentation task after the suite is green, using
`.specify/templates/ai-platform-quickstart-template.md`. Sections it will contain: (1) Architecture
context — cites delivery plan §3.3 row B1 and `17-ai-platform.md` §4.2 / §4.2.1 / §5.6 / §8.1;
(2) What was implemented — the `ai_internal` keystore, the `auth_internal` keypair routines and
issuer RPC, the `public` wrappers; (3) Files to review — the four migrations (incl. review overlay) and two SQL suites;
(4) Prerequisites — local Supabase stack up, `pgsodium` enabled by the migration; (5) Run the
automated suite — `psql -f backend/tests/ai_keystore_rls.sql` and `backend/tests/ai_token_issuer.sql`
(or `bash backend/tests/run_ai_platform_trust_tests.sh`); (6) Inspect the changes —
`\dn ai_internal`, `\df+ auth_internal.issue_ai_token`, a sample decoded AAT header; (7) Manual
validation omitted (CI is the only verification path — the slice exposes no user-facing behaviour).

### Source Code (repository root)

```text
backend/supabase/migrations/
├── 20260801120000_ai_keystore_schema.sql         # pgsodium enable, ai_internal schema, keystore + ledger tables, RLS deny, config keys
├── 20260801120100_ai_installation_keypair_routines.sql  # enroll / rotate / revoke keypair (auth_internal) + public wrappers
├── 20260801120200_ai_token_issuer_rpc.sql        # auth_internal.issue_ai_token + public.issue_ai_token; auth_internal.verify_aat self-test helper
└── 20260803140000_b1_review_resolution.sql       # review fixes overlay (public_jwk return, advisory lock, iss bind, grants, singleton trigger) — idempotent with updated originals

backend/tests/
├── ai_keystore_rls.sql                            # T01–T10 (public_jwk, rotation, verify iss/malformed, admin/error paths)
├── ai_token_issuer.sql                            # T07–T16 (claims, header alg, omissions, exact error codes, per-actor rate limit)
└── run_ai_platform_trust_tests.sh                 # runner for the two suites above
```

**Structure Decision**: B1 extends the existing `backend/` tree only. The keystore lives in a new
restricted `ai_internal` schema (matching §4.2 "restricted schema" and the clarification Q2); the
issuer and keypair routines live in `auth_internal` as `SECURITY DEFINER` with thin `public`
`SECURITY DEFINER` wrappers (EXECUTE revoked on internals), following the privileged clinic-function
pattern in `20260521110000_auth_rbac_definer_internal_schema.sql` (F4). No `ai-platform/` and no
`frontend/` files are created.

## Consumes Binding

B1's `Needs` cell is empty, so **there are no AI-platform Consumes entries**. The spec records one
**external** dependency (delivery plan §7): the existing clinic RBAC tables. Binding:

| Consumes (external) | Existing module binding |
| --- | --- |
| Supabase RBAC tables from which `scopes` are derived (spec §Clarifications / Assumptions; delivery plan §7 "Blocks B1") | `public.staff_members`, `public.staff_branch_assignments`, `public.branches`, `public.organizations`, `public.roles_permissions` (migration `20260516100000_auth_rbac_schema.sql`); AI scope seed `('owner'\|'administrator'\|'doctor', 'ai.access', true)` in `20260516100400_auth_rbac_seed.sql` and the full matrix `20260613140000_role_permissions_full_matrix.sql`. `scopes` = the caller's role's granted `permission_key` values in the `ai.*` namespace. |
| Existing claim-derivation primitive (§4.2 "resolve tenant/actor claims") | `auth_internal.build_staff_claims(p_user_id)` (migration `20260521110000_auth_rbac_definer_internal_schema.sql`), already the source of `staff_member_id`/`role`/`organization_id`/`branch_ids`. |

No entry lacks an existing implementation. No `Consumes` entry is modified (the no-rework rule,
delivery plan §2.3).

## Components Touched

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.2 Clinic backend components (Supabase) — **Installation keystore** + **AI token issuer RPC** | Yes | These are the two §4.2 rows the B1 `Canonical` cell names; §4.2.1 (sub-section of §4.2) names their mechanism. |
| §8.1 Clinic enrollment and trust bootstrap (clinic-side steps only) | Yes | The §8.1 clinic-side step "generate installation keypair / store private key in restricted schema" and the additive rotation described in §8.1's closing paragraph. The platform-side §8.1 writes (`installation`/`installation_key`/`entitlement`/`control_audit` in D1) are out of scope (B2). |

Only the §4.2 component group is touched, plus the clinic-side half of the §8.1 sequence (which is
part of the same component group's trust bootstrap, not a second §4 component). No gateway §4.3
component is touched.

## Files

Every file traces to an `FR-###` from `spec.md`. (Migrations are ordered lexicographically by
timestamp; each is idempotent and re-runnable, matching the existing migration convention.)

| File | Traces to |
| --- | --- |
| `backend/supabase/migrations/20260801120000_ai_keystore_schema.sql` | FR-001 (keystore in restricted schema, anon/authenticated denied), FR-002 (rotation is additive — schema permits multiple active rows per installation with distinct `kid`), FR-002b (singleton installation trigger), FR-003 (revoked key rejected — `revoked_at` column), FR-012 (issuance ledger row), FR-013 (rate-limit ledger counted within the configured window). Also `CREATE EXTENSION pgsodium` and `GRANT pgsodium_keymaker TO postgres` (enrollment definer role, §4.2.1). Schema `USAGE` to `postgres` only at B1 (`service_role` re-granted by F2 for `acceptance_targets`). |
| `backend/supabase/migrations/20260801120100_ai_installation_keypair_routines.sql` | FR-001, FR-002 / FR-002a (`rotate`/`enroll` return `public_jwk` + `kid` + `installation_id`; additive insert with `clock_timestamp()`), FR-003 (`revoke` sets `revoked_at`). Public `SECURITY DEFINER` wrappers; `REVOKE EXECUTE … FROM PUBLIC/anon/authenticated` on `auth_internal` B1 functions. |
| `backend/supabase/migrations/20260801120200_ai_token_issuer_rpc.sql` | FR-004–FR-013a: session gates, RBAC claims, EdDSA mint, issuance ledger, per-actor `pg_advisory_xact_lock` + rate limit, bare issuer exception codes; `verify_aat` returns `false` on malformed/`iss` mismatch and does not check `exp`. |
| `backend/supabase/migrations/20260803140000_b1_review_resolution.sql` | Same FRs as the three originals — applies review fixes on DBs that already ran `20260801120000`–`20260801120200` (idempotent `CREATE OR REPLACE` / grant overlay). |
| `backend/tests/ai_keystore_rls.sql` | T01–T10 (keystore access, `public_jwk`, rotation, previous-key verify, post-rotate mint kid, malformed/`iss` verify, revoked-key, admin FORBIDDEN, revoke/rotate errors). Suite ends in `ROLLBACK`. |
| `backend/tests/ai_token_issuer.sql` | T07–T16 (claim correctness, header `alg`, omissions, session codes, issuance row, per-actor rate limit, `exp`, remaining issuer codes). Restores rate-limit settings after mutation. |
| `backend/tests/run_ai_platform_trust_tests.sh` | Verification mechanics — runs the two SQL suites against the local stack, mirroring `run_auth_backend_tests.sh`. Also appended to that script's `sql_tests` array. |
| `specs/021-installation-keystore-aat-issuer/contracts/aat-token.md` | Freezes — the AAT JWS contract (header `{alg:"EdDSA", kid}`, §5.6 claim set, JWK `OKP`/`Ed25519` public-key format from §4.2.1, issuer error codes §9). Pinned by T07/T12 and keystore T05/T06. |
| `specs/021-installation-keystore-aat-issuer/quickstart.md` | Documentation task — slice-only quickstart per the template. |

## Test Layout

Every named test from `spec.md`'s Test plan is placed in the **SQL / RLS** layer (delivery plan
§3.11.2 row B1; §13.5 "Contract tests … CI, on every change"). The runner is
`backend/tests/run_ai_platform_trust_tests.sh`; the two suites follow the
`BEGIN … CREATE TEMP TABLE <name>_results … DO $$ … $$ … RAISE EXCEPTION on failure …`
pattern already used by `auth_security_extensions.sql` and `dev_reset_clinic_installation.sql`.
`ai_keystore_rls.sql` ends with `ROLLBACK`; `ai_token_issuer.sql` restores rate-limit settings it
mutates.

Numbering is **per suite** (keystore T01–T10; issuer T07–T16) — the labels overlap intentionally.

| Test | File | Layer | Construction |
| --- | --- | --- | --- |
| T01 keystore anon read denied | `ai_keystore_rls.sql` | SQL/RLS | `SET LOCAL role anon;` attempt to `SELECT` from `ai_internal.installation_keys` → `insufficient_privilege`. |
| T02 keystore authenticated read denied | `ai_keystore_rls.sql` | SQL/RLS | `SET LOCAL role authenticated;` SELECT → denied. |
| T03 enroll returns `public_jwk` | `ai_keystore_rls.sql` | SQL/RLS | Admin enroll; assert `rpc_success` data has `kid`, `installation_id`, and JWK `OKP`/`Ed25519`/`x`/`kid`. |
| T04 rotation additive + `public_jwk` | `ai_keystore_rls.sql` | SQL/RLS | Enroll, then rotate; assert two active rows and rotate payload includes `public_jwk`. |
| T05 previous-key verifies after rotation | `ai_keystore_rls.sql` | SQL/RLS | Mint under previous key, rotate, `verify_aat` true. Does **not** assert `exp` (B3). |
| T05b post-rotation mint uses new `kid` | `ai_keystore_rls.sql` | SQL/RLS | After rotate in same txn (`clock_timestamp` ordering), new mint header `kid` equals rotate result. |
| T05c malformed sig → false | `ai_keystore_rls.sql` | SQL/RLS | Tampered signature segment; `verify_aat` returns false, no throw. |
| T05d `iss` mismatch → false | `ai_keystore_rls.sql` | SQL/RLS | Payload `iss` ≠ key row `installation_id`; `verify_aat` false. |
| T06 revoked key rejected | `ai_keystore_rls.sql` | SQL/RLS | Mint, revoke, `verify_aat` false. |
| T07 keystore admin FORBIDDEN | `ai_keystore_rls.sql` | SQL/RLS | Non-admin enroll/rotate/revoke → `FORBIDDEN` via `rpc_result`. |
| T08–T10 revoke/rotate errors | `ai_keystore_rls.sql` | SQL/RLS | Empty kid → `INVALID_INPUT`; unknown kid → `KEY_NOT_FOUND`; rotate-before-enroll → `INSTALLATION_NOT_ENROLLED`. |
| T07 / T07b claims + header | `ai_token_issuer.sql` | SQL/RLS | Mint; assert claim correctness + header `alg: EdDSA` / non-null `kid`. |
| T08 / T08b scopes + omissions | `ai_token_issuer.sql` | SQL/RLS | Caller-supplied scopes ignored; deliberate-omission keys absent. |
| T09 session codes | `ai_token_issuer.sql` | SQL/RLS | Absent → `UNAUTHENTICATED`; expired → `SESSION_EXPIRED` (after enrollment). |
| T10 issuance row | `ai_token_issuer.sql` | SQL/RLS | One ledger row per `jti`. |
| T11 rate limit | `ai_token_issuer.sql` | SQL/RLS | Ceiling exceeded → `RATE_LIMITED`; other actor still mints (advisory lock path). |
| T12 `exp` window | `ai_token_issuer.sql` | SQL/RLS | `0 < exp − iat ≤ configured_minutes`. |
| T13–T16 issuer codes | `ai_token_issuer.sql` | SQL/RLS | `STAFF_NOT_FOUND`, `BRANCH_NOT_FOUND`, `INSTALLATION_NOT_ENROLLED`, `AI_ACCESS_DENIED`. |

No named test is unplaceable. No test is pulled forward from B2/B3/B4.

## Sequencing

Tests land **alongside** implementation, per the delivery plan's testing-first intent and §3.10
(coverage is behavioural; the suite is the review artifact). Concretely, the plan implements in
this order so each step is independently green:

1. **Keystore schema first** (`20260801120000_ai_keystore_schema.sql`) — `CREATE EXTENSION
   pgsodium`, `ai_internal` schema, keystore + ledger tables, RLS, config keys. Then write
   `ai_keystore_rls.sql` T01–T03 and run; they pass against the schema alone.
2. **Keystore routines** (`20260801120100_ai_installation_keypair_routines.sql`) — enroll/rotate/
   revoke. Then T04–T06 (rotation additivity, previous-key verifies, revoked-key rejects). T05/T06
   use `auth_internal.verify_aat`, which is added with the issuer in step 3 — so T05/T06 are
   written here but executed after step 3 lands; T04 passes now.
3. **Issuer RPC** (`20260801120200_ai_token_issuer_rpc.sql`) — `issue_ai_token`, `verify_aat`,
   public wrappers. Then issuer T07–T16. Now the full keystore suite (T01–T10) also passes.
4. **Runner + CI wiring** (`run_ai_platform_trust_tests.sh`, appended to
   `run_auth_backend_tests.sh`). Full B1 suite green.
5. **Documentation task** — write `contracts/aat-token.md` (frozen contract, pinned by T07/T12)
   and `quickstart.md`.
6. **Review-resolution overlay** (`20260803140000_b1_review_resolution.sql`) — applied after the
   original three migrations for DBs that already ran them; originals were updated in lockstep so
   fresh resets need no separate behavioural delta.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. The only deviation from a
> plain pattern is the use of the `pgsodium` extension, and that is **named by the cited
> architecture** (§4.2.1), not a complexity introduced by the plan.