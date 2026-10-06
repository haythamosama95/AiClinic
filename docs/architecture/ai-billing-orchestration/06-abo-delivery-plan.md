# AI Billing Orchestrator — Delivery Plan

Status: approved for implementation · Date: 2026-10-02
Scope: implements the ABO design in docs 02–05.

## Table of Contents

1. [How to use this plan](#1-how-to-use-this-plan)
2. [Plan structure](#2-plan-structure)
3. [E2E verification strategy](#3-e2e-verification-strategy)
4. [Phases and units](#4-phases-and-units)
5. [Coverage and traceability](#5-coverage-and-traceability)
6. [Open questions and defaults](#6-open-questions-and-defaults)

---

## 1. How to use this plan

**Who executes it.** Every unit below is implemented by an AI model using Spec Kit. One unit is exactly one Spec
Kit feature (`specs/<NNN>-abo-p<phase>-<n>-<slug>/`): specify, clarify, plan, tasks, implement. Phases only group
units and mark checkpoints; a phase has no spec of its own.

**Nothing ships before the end.** The product goes live once, after phase P8. A unit does not need to be
deployable on its own, but when it finishes, its E2E scenarios must pass in the named local harness and every
earlier suite must still be green.

**What an implementer reads.** For unit `P<k>.<n>`, read only:

1. sections 2 and 3 of this plan (rules and harnesses, once per session);
2. that unit's section in section 4 of this plan;
3. the design sections listed in the unit's **Read** line, and nothing in its **Do not read** line;
4. the code paths listed in the unit's **Code** line.

**Design source.** Every reference written like `03 §2.4` means the design docs in
`docs/architecture/ai-billing-orchestration/`: `00` requirements seed, `01` design decisions, `02` architecture
and threat model, `03` data model and lifecycle, `04` contracts, `05` operations and traceability.

**Unit tests are not listed here.** Each unit's implementer decides its unit tests. This plan fixes the E2E
scenarios: their IDs and meaning are copied into the unit's `spec.md` verbatim. An implementer may add scenarios
but never drop one.

**Unit index.** Sizes: S = 12–20 tasks, M = 20–32, L = 32–40 (rule S3).

| Unit | Title | Size | Depends on |
| ---- | ----- | ---- | ---------- |
| P1.1 | Membership, active organisation and `current_org_id()` | L | — |
| P1.2 | Tenant scoping of shared state and the cross-tenant suite | L | P1.1 |
| P2.1 | Package core: canonical JSON, signing, identifiers, version constants | M | — |
| P2.2 | Package contracts: message types, WebAuthn, Access JWT and the testkit | M | P2.1 |
| P3.1 | `VendorEntrypoint`, authorization classes, operator credentials and platform alerting | L | P2.2 |
| P3.2 | Issuer tokens, issuer-key registry and tenant bindings | M | P3.1 |
| P3.3 | Plan versions, paid-grant intake and the per-clinic coverage ledger | L | P3.2 |
| P3.4 | Admission and settlement against terms | L | P3.3 |
| P3.5 | Term boundaries, grace and renewal | M | P3.4 |
| P3.6 | Complimentary grants, ceilings, term adjustments and suspension | M | P3.5 |
| P3.7 | Reversal voids, tombstones, held terms and operator voids | M | P3.6 |
| P3.8 | Transfer, deletion with coverage left, and ledger retention | L | P3.7 |
| P3.9 | Fallback admission, coverage feed and administrator coverage read | M | P3.5 |
| P3.10 | Control-plane port to `VendorEntrypoint` and removal of `/control/*` | L | P3.8, P3.9 |
| P3.11 | Platform rebuild procedures and the write budget | M | P3.10 |
| P4.1 | ABO skeleton, records layer, billing-token auth and catalogue reads | L | P2.2 |
| P4.2 | Checkout creation, Paymob intention, coverage view and the cross-worker harness | L | P4.1, P3.3 |
| P4.3 | Notification intake, inquiry, work pipeline and payment confirmation | L | P4.2 |
| P4.4 | Grant pipeline to the platform: purchase to AI on | M | P4.3, P3.4 |
| P4.5 | Sweeps, reversals and the inquiry budget | L | P4.4, P3.7 |
| P4.6 | Operator console: Access perimeter, lookup, views and class-H ABO actions | M | P4.5, P3.6 |
| P4.7 | Console passkey ceremony and ABO-side HP actions | M | P4.6, P3.1 |
| P4.8 | Console relays: complimentary grants, adjustments, voids, suspension, deletion and the transfer saga | M | P4.7, P3.8 |
| P4.9 | Console relays: platform configuration, registries and bootstrap | M | P4.7, P3.10 |
| P4.10 | Reconciliation, payout import and findings | M | P4.8 |
| P4.11 | Daily digest, platform watch, housekeeping and ABO rebuild | M | P4.10, P3.9 |
| P5.1 | Issuer key custody, token issuance and the versioned RPC envelope | L | P1.2, P3.2, P4.1 |
| P5.2 | Coverage feed puller, status projection and status RPCs | L | P5.1, P3.9 |
| P6.1 | Desktop contract versions, token minting and AI status reads | M | P5.2 |
| P6.2 | Desktop denial states and the administrator coverage view | M | P6.1 |
| P6.3 | Administrator billing: offers, contact and checkout flow | L | P6.1, P4.5 |
| P6.4 | Administrator subscription, payment history and commercial notices | M | P6.3 |
| P7.1 | Clean-up of dependent paths and the `/control` residue guard | S | P3.10, P4.9 |
| P7.2 | Cross-system security and isolation suite | M | P6.4, P4.11 |
| P7.3 | Contract version matrix | M | P6.4, P4.11 |
| P8.1 | Staging environment, external monitors and the staging profile | M | P7.1 |
| P8.2 | Staging acceptance A1–A36 | L | P8.1, P7.2, P7.3 |
| P8.3 | Launch readiness checks | S | P8.2 |

---

## 2. Plan structure

Rules in this section are labelled S1–S12; rules in section 3 are labelled V1–V8. Unit sections cite them as
"rule S9" or "rule V2". Labels such as A1–A36 always mean the acceptance scenarios of 05 §8.

**S1. Phases with sub-phases; the leaf is the sub-phase.** Phases P1–P8 map 1:1 to the eight steps of
05 §6.3, so the design's own sequence stays traceable. Each step is far too big for one cheap-model Spec
Kit run (step 3 alone touches ~40 platform files, 04 §6.1), so every phase is split into sub-phases.
A phase is only a grouping and a checkpoint boundary; it has no spec of its own.

**S2. A leaf unit = exactly one Spec Kit feature** (`specs/<NNN>-abo-<slug>/`, one branch
`ai/<NNN>-abo-<slug>`, one review), run as specify → clarify → plan → tasks → implement. "Done" means its
E2E scenarios (listed in the unit section) pass in the named harness and every earlier suite is still green. Being
independently shippable is not a criterion (nothing ships before P8).

**S3. Sizing target per leaf.**

| Size | tasks.md | User stories | v2 doc subsections to read | Codebases |
| ---- | -------- | ------------ | -------------------------- | --------- |
| S | 12–20 | 1–2 | ≤ 4 | 1 |
| M | 20–32 | 2–3 | ≤ 7 | 1 (plus thin wiring into a second only where named) |
| L | 32–40 | 3–4 | ≤ 9 | 1 |

There are no XL units. Stop condition: if `tasks.md` goes past 40 tasks, stop before implementing and
split the unit along its user stories into `<ID>a`/`<ID>b`, keeping the same scenario IDs. A unit
touches one codebase unless its row names a wiring exception (P2.1 platform header wiring; P5.1 the
full-stack harness; P7.1 viewer + scripts + docs).

**S4. IDs and Spec Kit numbering.** Unit IDs are `P<phase>.<n>`; they never change. Spec numbers are
**pre-assigned in plan order, starting at 061** (table below), not at start time, so parallel tracks
cannot collide. Directory slug: `abo-p<phase>-<n>-<short-name>`. The `AGENTS.md` SPECKIT block is
updated to the active unit when its specify step starts.

| Phase | Unit = spec number |
| ----- | -------------------- |
| P1 | P1.1=061, P1.2=062 |
| P2 | P2.1=063, P2.2=064 |
| P3 | P3.1=065, P3.2=066, P3.3=067, P3.4=068, P3.5=069, P3.6=070, P3.7=071, P3.8=072, P3.9=073, P3.10=074, P3.11=075 |
| P4 | P4.1=076, P4.2=077, P4.3=078, P4.4=079, P4.5=080, P4.6=081, P4.7=082, P4.8=083, P4.9=084, P4.10=085, P4.11=086 |
| P5 | P5.1=087, P5.2=088 |
| P6 | P6.1=089, P6.2=090, P6.3=091, P6.4=092 |
| P7 | P7.1=093, P7.2=094, P7.3=095 |
| P8 | P8.1=096, P8.2=097, P8.3=098 |

Total: 38 units, specs 061–098. If a unit splits under the rule S3 stop condition, the halves share its number with suffixes `a`/`b` (e.g. `068a`, `068b`).

**S5. The tenancy retrofit is in scope (P1.1, P1.2).** The design names it as precondition 1 (05 §6.3,
01 R-1) and as a launch condition (05 §6.2). Without it SR-03, SR-08 and A36 cannot pass (05 §10), and
the product launches only when everything is done. It is backend-only and runs in parallel with P2–P4.
Key decision for P1.1: re-point the existing `public.jwt_organization_id()` (115 dependent migrations)
to the new membership-checked `current_org_id()`, rather than rewriting every policy.

**S6. Spikes live in the research step of the first unit that consumes them.** They are not separate
units: Spec Kit's `research.md` is where they belong. Each must record its outcome and, if it fails, pick
the fallback the design names (05 §10 "Spike-dependent items"). R-5 → P2.2 (WebAuthn/ES256) and P3.1
(Access `amr`, service-binding caller identity); R-2 → P4.2 (intention expiry default) and P4.3
(redelivery, second success, order listing, rate limits); R-3 → P5.1; R-4 → P5.2 (local, then confirmed
in P8.1); R-6 → P8.1; R-7 → P3.11. OQ-3 covers the accounts these need.

**S7. Contract-first ordering and freezing.** P2.1/P2.2 freeze the shared package
(`packages/vendor-contracts/`, a `file:` dependency) before any consumer. Platform units freeze each
`VendorEntrypoint` method when they implement it. The ABO calls only methods that are already frozen,
and it calls them through the real platform worker, never a hand-written stub. No-rework rule (reused
from the AI Platform (AP) plan §2.3): a later unit may extend a frozen contract but never rewrite one. If a
contract is wrong, amend the v2 design doc first and then return. Design deviations recorded here:
Access-JWT verification is placed in the shared package, next to WebAuthn, so both Workers use one
copy. P3.1 credential results stay inside the frozen result envelope: it does not grow, `receipt` stays
required exactly when `result` is `applied` or `already_applied`, and `registerOperatorCredential`,
`revokeOperatorCredential`, and `listOperatorCredentials` return `ok` with the credential row or the
active-key list as JSON text in `detail`. They do not return `applied` or `already_applied`, which
require a grant or reversal receipt. Each unit creates its own migration files with fresh, increasing timestamps; 04 §6.3 file names
are indicative only, and the union of the contents must equal 04 §6.3.

**S8. No unwired modules (the Band I lesson).** Every module a unit adds must be reached by at least one
of that unit's E2E scenarios from a **live entry point**: an HTTP route (`SELF.fetch`), a `VendorEntrypoint`
method over a real service binding, the `scheduled()` handler, a DO alarm, a PostgREST RPC, a pg_cron job,
or a Flutter widget composed in the real app shell. `quickstart.md` lists entry point → module chain per
scenario. Library-only work is allowed only in P2.2 (and the package half of P2.1), verified by
conformance vectors run in both Node and workerd; its testkit is consumed by every later harness.

**S9. Transitional states are explicit.** The platform track keeps the old path alive until the unit that
replaces it: enrollment is removed in P3.2; `/control/entitle` keeps test clinics admitted until P3.4
switches admission to terms; entitlement/plan/invoice tables and all `/control/*` routes are removed in
P3.10. Each unit's Out-of-scope list names the transitional item and its owner.

**S10. Parallelism.** Three tracks after P2.2: platform (P3.x, sequential, except that P3.9 may run
in parallel with P3.6–P3.8), ABO (P4.x), and backend tenancy (P1.x, which can start on day 1). The ABO starts with P4.1
alongside P3.1 and joins the platform at P4.2 (needs P3.3), P4.4 (needs P3.4), P4.5 (needs P3.7), P4.8
(needs P3.8), P4.9 (needs P3.10). Backend P5.x needs P1.2 + P3.2/P3.9; desktop P6.x needs P5.2. Two units
in the same codebase never run concurrently, except P3.9 as noted.

**S11. Review checkpoints** (composition checks, not shipping gates; each needs all prior suites green):

| CP | After | Question |
| -- | ----- | -------- |
| CP-A | P2.2 | Do the frozen package contracts work in both runtimes, and are the vectors consumable by SQL/Dart? |
| CP-B | P3.4 | Falsification: does a paid grant over the real entrypoint, then an issuer token, give a completed live `POST /v1/requests` charged to a term? |
| CP-C | P4.4 | Does purchase → callback → inquiry → grant → AI on run across the real ABO and platform workers with the Paymob stub (local A1)? |
| CP-D | P5.2 | Does a platform coverage event reach `get_ai_status()` through local Supabase within the bound? |
| CP-E | P6.3 | Does one thread go from the admin desktop client to checkout, payment, grant, status and an AI request? |
| CP-F | P7.3 | Is the design fully implemented? Diff 02–05 against the code, no `/control/*` residue, version matrix green. Gate to staging |
| CP-G | P8.2 | All A1–A36 pass on staging. Launch gate (FR-90) |

**S12. Spec authoring protocol** (adapted from AP plan §6). Each `spec.md` carries: **Implements** (the v2
§ list from its row), **Freezes**, **Consumes**, **Requirements**, **E2E scenarios** (the IDs from its row,
copied verbatim; an implementer may add scenarios but never drop one), **Out of scope** (copied verbatim),
**Spikes** (if any). The authoring job is transcription: stop and escalate if a requirement is not
traceable to v2 02–05, or if a Consumed contract would need to change. Each `plan.md` re-runs the
constitution check (02 §7).

---

## 3. E2E verification strategy

**V1. Harness layers** (one owner each; later units extend, never fork):

| ID | Harness | Where | Built / extended by |
| -- | ------- | ----- | ------------------- |
| H-PKG | Package conformance: golden vectors in Node and in the workers pool | `packages/vendor-contracts/test/` | P2.1, P2.2 |
| H-AP | Platform system harness: `SELF.fetch`, real D1/R2/DO, plus a **self service binding to `VendorEntrypoint`** | `ai-platform/test/system/` (+ `test/e2e/`) | exists; P2.1 adds the version header, P3.1 entrypoint/operator helpers, P3.2 issuer tokens, P3.4 grant-based setup, P3.10 removes `/control/*` |
| H-ABO | ABO system harness: `SELF.fetch` with Host header for the billing/ops hostname, billing-token minting, D1/R2 helpers, `runScheduled`, email capture | `abo/test/system/` | P4.1 |
| H-PAY | Paymob stub (an auxiliary worker scripted per test: auth token, intention, order inquiry, transaction endpoints; bound/unbound, mismatch, pending, reversed, timeout, rate limit) + **HMAC replay fixture** (recorded bodies re-signed with a local secret: success, decline, parent-flag refund, child refund, bad HMAC, replay) | `abo/test/stubs/paymob/`, `abo/test/fixtures/paymob/` | P4.2 (intention), P4.3 (callbacks + inquiry), P4.10 (payout CSV) |
| H-XW | Cross-worker: ABO tests run the **real ai-platform worker** as an auxiliary Miniflare worker, bound as `PLATFORM` with `entrypoint = "VendorEntrypoint"`; the platform is built from source before the run | `abo/test/system/` + build script | P4.2 |
| H-BK | Backend SQL harness (existing psql suites + catalog) on local Supabase; **new backend CI job** | `backend/tests/` | P1.1 (CI), P1.2 onward |
| H-FS | Full stack: `supabase start` + `wrangler dev` for the platform and ABO + Paymob stub server + Node scenario runner (supabase-js as real test users). The same runner is pointed at staging in P8 | new top-level `e2e/fullstack/` (own package.json, `file:` dep on the package) | P5.1 (+ CI job), P5.2 (pg_net to the host) |
| H-FL | Flutter: Dart client tests against H-FS (tag `fullstack`) for real network behaviour; widget scenario tests with fake ports for UI states. No `integration_test/` desktop driver (OQ-6) | `frontend/test/integration/`, `frontend/test/widget/` | P6.1 |
| H-STG | Staging runner = H-FS runner with staging config, Paymob test cards, `DURATION_SCALE`; manual steps scripted as checklists | `e2e/fullstack/staging/` | P8.1, P8.2 |

**V2. Migrating the existing `/control/*`-based harnesses.** Today's system and e2e suites and the viewer
set up state through `/control/*` with `OPERATOR_BEARER_TOKEN` (`operatorFetch`, `enrollScenario`,
`entitleScenario`, `test/e2e/harness/control.ts`, `env.ts`). The design removes these. Migration is
staged, and **P3.10 owns its completion**:
- P3.1 adds entrypoint helpers (`vendorCall(method, args, {accessJwt, assertion})`, built on the P2.2
  testkit) next to `operatorFetch`.
- P3.2 replaces `enrollScenario` with `newClinic()`: it registers the test issuer key and mints issuer
  tokens. Every suite that enrolls is migrated in P3.2.
- P3.4 replaces `entitleScenario` with `coverClinic()`, a paid grant signed with the testkit ABO key over
  the entrypoint. Every suite that entitles is migrated in P3.4.
- P3.10 ports the remaining operator setup (routing policy, kill switch, cohort, capability lifecycle,
  token contract, support lookup) to entrypoint helpers. It deletes `operatorFetch`/`operatorFetchRaw`,
  rewrites `test/e2e/harness/control.ts` and `env.ts`, deletes and rewrites suites per 04 §6.5, and
  removes the `OPERATOR_BEARER_TOKEN` binding from both vitest configs.
- P7.1 migrates the viewer (`ai-platform-viewer/`, catalog smoke tests) and `docs/testing/catalog/` stage
  pages that describe `/control/*` probes (they are marked superseded or rewritten to entrypoint terms).

**V3. Scenario IDs.** `E2E-P<phase>.<n>-<NN>` (e.g. `E2E-P3.4-07`), used as the vitest/Dart/psql test title
prefix, one test per ID (matching the existing `SYS-<suite>.<n> — …` convention). Each scenario line in
each unit section names, in brackets, the acceptance IDs (A#), alerts (AL-#), failure modes (FM-#) and
requirement IDs it evidences. Staging scenarios are `STG-A01` … `STG-A36` plus `STG-FM-nn`. **Rule:** P8.2
maps every A1–A36 to at least one STG scenario and cites the earlier E2E IDs that first verified it
(listed in section 5, D2). An A# with no earlier local E2E is a CP-F finding.

**V4. Time.**
- **Test clock (primary, local).** Each Worker reads time through one clock module. Only the test vitest
  configs bind a test-only clock control; harnesses advance it and fire DO alarms
  (`runDurableObjectAlarm`) and crons (`runScheduled`). A config test asserts that the production and
  staging wrangler envs carry no clock control. Introduced on the platform in P3.1 (24-hour credential
  activation, 5-minute assertion freshness) and in the ABO in P4.1. No local scenario may sleep more
  than 2 s of real time.
- **`DURATION_SCALE` (03 §6.1, 05 §6.1).** Implemented in P3.3 (calendar) and P3.5 (boundaries). It is
  verified locally with the test clock: a monthly term under the staging scale spans exactly 30 minutes
  and grace about 7 minutes. Units are computed unscaled, then scaled.
- **Real compressed time** is used only where a test clock cannot reach across systems: H-FS (pg_cron
  pulls) and H-STG. H-FS may set a faster scale that keeps the design's 30:1 month:day ratio
  (1 month = 60 s, 1 day = 2 s); staging uses exactly the 05 §6.1 values. OQ-5.

**V5. Version matrix (05 §6.1, 04 §7).** Every unit tests its own channels for "current N accepted and
echoed" and "missing or unsupported → refusal before authentication and before any write". The
cross-deploy matrix (N, N−1, unsupported; ABO on N+1 against a platform on N; stored payloads retried in
their original version) is owned by **P7.3**. It builds test variants with overridden package
constants, because every channel is at version 1 at launch.

**V6. Alerts and external effects in tests.** `send_email` is asserted by capturing what is handed to the
binding (body has codes and ids only, TB-9). Heartbeat pings are asserted by capturing the outbound fetch
to the configured URL. The external monitor and audit watcher exist only from P8.1.

**V7. CI.** New jobs: package (P2.1), backend SQL on local Supabase (P1.1), ABO system (P4.1), ABO↔platform
cross-worker (P4.2), import-boundary check G6 (P4.2), full stack (P5.1), Flutter `fullstack` tag (P6.1),
`/control` residue guard (P7.1). Existing platform and frontend jobs stay green throughout.

**V8. Failure-path rule.** Each unit's scenario list includes every refusal code it introduces and every
FM-# that section 5, D1 assigns to it. Fault injection uses the harness: forcing the DO to throw, D1/R2 binding
failures, stub scripts, a stopped Supabase or worker in H-FS.

---

## 4. Phases and units

Each unit section uses the same fields, in this order: **Spec** (pre-assigned Spec Kit number) · **Codebase** · **Size** ·
**Depends** · **Parallel**; **Read** (v2 design sections, minimal set) and **Do not read**; **Code** (existing paths to
inspect); **Implements**; **Out of scope** (with the owning unit); **Inputs**; **Outputs / freezes** (artifacts and the
contracts later units consume unchanged); **E2E** (harness, then one scenario per line). Tags in square brackets on a
scenario name what it evidences: acceptance scenarios (A#), alerts (AL-#), failure modes (FM-#), trust boundaries (TB-#),
adversaries (AD-#), credentials (K-#) and seed requirement IDs.


## Phase P1 — Tenancy retrofit (05 §6.3 step 1; 01 R-1)

### P1.1 — Membership, active organisation and `current_org_id()`
- **Spec** 061 · **Codebase** backend · **Size** L · **Depends** — · **Parallel** P2.x, P3.x, P4.1
- **Read:** 01 §2 rows T-1, T-2, T-5; 01 §7 row R-1; 03 §1 (last row) and 03 §4 (first row "Tenancy");
  02 §2 row TB-4; 02 §4.3 row "Tenant isolation"; 04 §2.1 (first paragraph: `org` from `current_org_id()`).
- **Do not read:** 03 §2–§3, 04 §1, §5–§6 (vendor-side).
- **Code:** `20260516100000_auth_rbac_schema.sql` (:54-58 `rpc_result`, :116-131), `20260516100200_auth_rbac_rls.sql:59`
  (`jwt_organization_id`), `20260611150000_remove_owner_role.sql` (:8-30 roles, :870-875 first-org claim),
  `backend/supabase/config.toml` (auth hooks), `backend/tests/run_all_backend_tests.sh`, `backend/tests/catalog/`.
- **Implements:**
  - `membership (user_id, organization_id, role)`; backfill one membership per existing staff user (current org, current role).
  - Active organisation per session: the per-user active-org record `user_active_organization (user_id PK,
    organization_id, updated_at)` (03 §4 Tenancy row), plus an auth access-token hook that puts the
    `active_org` claim in the JWT; RPC `set_active_organization(p_organization_id)` (membership required).
    The RPC returns `public.rpc_result`; without a membership in the named organisation it answers
    `rpc_error('FORBIDDEN', ...)` (`success = false`) and leaves the record unchanged, so the claim is
    unchanged on refresh.
  - `current_org_id()`: active-org claim, valid only while a live membership exists (re-checked on every call;
    otherwise NULL, and definer RPCs raise). `current_membership_role()`.
  - Claim compatibility for `current_org_id()`: the active-org claim is `active_org`; a JWT that carries no
    `active_org` claim — a pre-retrofit token, or the pre-existing H-BK suites' psql impersonation, which sets
    only `organization_id` (e.g. `backend/tests/rls_isolation.sql`) — falls back to the legacy `organization_id`
    claim. Whichever claim names the organisation, the membership re-check is unchanged: the organisation is
    returned only while a live membership `(sub, org)` exists, so a crafted claim without a membership is still
    treated as no organisation (E2E-P1.1-05).
  - Re-point `public.jwt_organization_id()` to `current_org_id()`, so the existing dependents inherit the re-check.
  - Billing authority = membership role `administrator` (T-2, I-1), never `roles_permissions`.
  - Backend CI job: local Supabase, all migrations, `run_all_backend_tests.sh` + catalog harness (H-BK in CI).
- **Out of scope:** per-tenant `roles_permissions` and the org audit of tables and RPCs (→ P1.2); token changes (→ P5.1);
  a desktop organisation switcher (not in the design, OQ-2).
- **Inputs:** existing auth/RBAC migrations.
- **Outputs / freezes:** `current_org_id()` and `current_membership_role()` semantics (consumed by P1.2, P5.1, P5.2); migrations; backend CI job.
- **E2E (H-BK, psql impersonating JWT users):**
  - E2E-P1.1-01 One-membership user signs in → the claim carries that org; `current_org_id()` = org.
  - E2E-P1.1-02 User in orgs A and B calls `set_active_organization(B)` and refreshes → `current_org_id()` = B; tenant RPCs return only B rows.
  - E2E-P1.1-03 `set_active_organization(C)` without membership → `rpc_result` with `success = false` and `error_code = 'FORBIDDEN'`; the active-org record and the claim unchanged.
  - E2E-P1.1-04 Membership deleted while the JWT is still valid → `current_org_id()` NULL; RLS selects return 0 rows; definer RPC raises [SR-03].
  - E2E-P1.1-05 Crafted JWT with an org the user has no membership in → treated as no org [A36 backend].
  - E2E-P1.1-06 `current_membership_role()` = administrator vs doctor; editing `roles_permissions` does not change it [T-2].
  - E2E-P1.1-07 Backfill: every pre-existing staff user has exactly one membership matching its org/role.
  - E2E-P1.1-08 Regression: every pre-existing backend suite stays green with its impersonated claims and its
    assertions unchanged. Those suites impersonate `request.jwt.claims` with `organization_id` and insert their
    fixture users after the backfill, so P1.1 — as H-BK owner (rule V1) — adds to each such suite's fixture
    setup the membership row each impersonated fixture user needs (the fixture user, the organisation its claim
    names, the fixture staff role), mirroring the backfill rule. A suite that deliberately impersonates a user
    with no fixture staff/membership row keeps asserting denial.

### P1.2 — Tenant scoping of shared state and the cross-tenant suite
- **Spec** 062 · **Codebase** backend · **Size** L · **Depends** P1.1 · **Parallel** P2.x, P3.x, P4.x
- **Read:** 01 §2 rows T-1–T-3; 01 §7 row R-1 ("`organization_id` on all AI and billing state"); 02 §4.2 rows
  AD-2, AD-3; 04 §3.1 (intro paragraph only); 05 §8 row A36.
- **Do not read:** 04 §3.2–§3.3 (status RPCs, P5.2).
- **Code:** every `SECURITY DEFINER` function and RLS policy in `backend/supabase/migrations/`; `roles_permissions`
  (`20260516100000_auth_rbac_schema.sql:163-176`); `staff_members`, `staff_branch_assignments`; AI tables in `ai_internal`.
- **Implements:**
  - An inventory (in `research.md`) of every tenant table, policy and definer RPC, with its org key; fix each to key on `current_org_id()`.
  - `organization_id` + RLS on AI state lacking it (`ai_internal.ai_token_issuance`, AI acceptance records), and on any tenant table found without one.
  - Per-tenant `roles_permissions` (organization_id column, policies, seed per org), so one tenant's admin cannot change another's AI scopes [T-2].
  - Staff and branch assignment rows tied to org through membership.
  - A two-org, two-admin cross-tenant suite in `backend/tests/`.
- **Out of scope:** installation keys and the single-installation trigger (→ P5.1); availability flag (→ P5.2).
- **Inputs:** P1.1 helpers. **Outputs / freezes:** the tenant inventory; per-tenant `roles_permissions`; cross-tenant suite (re-run by P7.2).
- **E2E (H-BK):**
  - E2E-P1.2-01 Admin of A edits `roles_permissions` → B's permissions and B's AI scopes unchanged.
  - E2E-P1.2-02 User of A calls every tenant RPC in the inventory with B's ids → not found or empty; B rows unchanged [A36, SR-08].
  - E2E-P1.2-03 Direct PostgREST reads by A of every inventoried table → zero B rows.
  - E2E-P1.2-04 Dual-membership user switches active org → sees only the active org's data, including staff and branches.
  - E2E-P1.2-05 Existing AI RPCs (`record_ai_acceptance`, `issue_ai_token` as today) write `organization_id = current_org_id()`.
  - E2E-P1.2-06 Regression: all backend suites green.

---

## Phase P2 — Shared contract package and versioning (05 §6.3 step 2)

### P2.1 — Package core: canonical JSON, signing, identifiers, version constants
- **Spec** 063 · **Codebase** `packages/vendor-contracts/` (new) + thin wiring in `ai-platform/` · **Size** M · **Depends** — · **Parallel** P1.x
- **Read:** 02 §1.2 (opening paragraph only); 04 §1.1 ("Canonical form" bullet); 04 §6.2 (last paragraph); 04 §7 (all);
  03 §7; 04 §4.2 (first paragraph + `contract_version_unsupported` row).
- **Do not read:** 04 §1.2–§1.7 (→ P2.2).
- **Code:** `ai-platform/src/worker.ts` (`/v1/*` dispatch, SSE response creation), `ai-platform/package.json`, `ai-platform/test/system/harness.ts`.
- **Implements:**
  - Package skeleton (TypeScript ESM, builds for workerd and Node), consumed by `ai-platform` as a `file:` dependency, with wrangler bundling proven.
  - RFC 8785 canonicalisation; SHA-256 hex; Ed25519 compact JWS sign/verify (`alg=EdDSA`, `kid`) on WebCrypto.
  - 03 §7 identifiers: subscription ref `AIC-…`, `payment_id`, the three `grant_id` forms, coverage `event_id`, `CK-/PAY-/REV-/GR-` refs, ULID (80 random bits), Crockford base-32.
  - Per-channel version constants (04 §7.1, all = 1); negotiation helper (accept N and N−1, answer in the request's version; refusal `{code: contract_version_unsupported, accepted_versions}`).
  - Golden vector files (canonical bytes, hashes, identifiers, JWS) for later SQL (P5.2) and Dart (P6.1) contract tests.
  - Platform wiring: `src/vendor/contract-version.ts`; `Aip-Contract-Version` checked before token verification and echoed on every
    clinic `/v1/*` response, sent before the first SSE byte. H-AP harness sends it by default. Package CI job.
- **Out of scope:** message types, WebAuthn, Access, testkit (→ P2.2); entrypoint version checks (→ P3.1); feed route (→ P3.9);
  backend and Dart copies of the constants (→ P5.1, P6.1).
- **Outputs / freezes:** canonical, hash and JWS APIs; identifier functions + vectors; channel constants and the refusal shape.
- **E2E (H-PKG + H-AP):**
  - E2E-P2.1-01 Canonical bytes of every vector object equal the fixture in Node and in workerd.
  - E2E-P2.1-02 JWS signed in Node verifies in workerd and the reverse; a changed payload or `kid` fails.
  - E2E-P2.1-03 Identifier vectors: subscription ref of the fixture org; `grant_id(paid)` = SHA-256("grant:paid:" ‖ payment_id).
  - E2E-P2.1-04 `POST /v1/requests` without `Aip-Contract-Version` (and with an invalid token) → 400 `contract_version_unsupported` + `accepted_versions`; no `ai_request` row [NFR-09].
  - E2E-P2.1-05 `GET /v1/capabilities` with version 1 → header echoed; version 2 → 400.
  - E2E-P2.1-06 Streamed request: the response header is present before the first SSE event.
  - E2E-P2.1-07 All existing system and e2e suites green with the header.

### P2.2 — Package contracts: message types, WebAuthn, Access JWT and the testkit
- **Spec** 064 · **Codebase** `packages/vendor-contracts/` · **Size** M · **Depends** P2.1 · **Parallel** P1.x
- **Read:** 04 §1.2; 04 §1.4 (field table only); 04 §1.5; 04 §1.6; 04 §1.7; 04 §2.1; 04 §4.1 (the sentence defining each event, only); 02 §3.3; 01 §7 row R-5 (spike).
- **Do not read:** 04 §1.3 method semantics (names only), 03 §6.
- **Implements:**
  - Types + runtime validators: result envelope, grant envelope, receipt, coverage snapshot, feed event, operation object, AI/billing/feed token claims.
  - WebAuthn: assertion verification (rpId, origin, `type`, UP+UV flags, ES256 DER→raw, EdDSA); attestation parsing for registration;
    challenge = base64url(SHA-256(canonical operation object)).
  - Access JWT verification (team certs injected, issuer, `aud` tag, expiry) → email. Deviation recorded in rule S7: in the package, not per Worker.
  - `testkit` subpath export, which production code must never import: a software authenticator (ES256 + EdDSA; attestation and assertion),
    an Access team key + JWT minter + certs document, an issuer key set + minters for the three audiences, an ABO grant-key signer,
    a platform receipt signer.
  - R-5 spike result recorded (ES256 conversion, whether `amr` is meaningful).
- **Out of scope:** where each check is enforced (→ P3.1 platform, P4.6/P4.7 ABO).
- **Outputs / freezes:** the message types of 04 §1.2–§1.7 and §2.1; the verification APIs; the testkit API (used by every later harness). CP-A.
- **E2E (H-PKG, Node + workerd):**
  - E2E-P2.2-01 A testkit assertion over operation O verifies; the same assertion against O′ (one param changed) fails [AD-8 substitution].
  - E2E-P2.2-02 UV flag cleared, wrong origin, or wrong rpId → each fails.
  - E2E-P2.2-03 ES256 and EdDSA credentials both verify; another alg is rejected [R-5].
  - E2E-P2.2-04 Access JWT: valid → email; wrong `aud` tag, expired, or unknown cert kid → fails.
  - E2E-P2.2-05 Grant envelope: canonical hash stable; ABO signature verifies, and fails after any field mutation.
  - E2E-P2.2-06 Receipt signature verifies; tampered `term_ids` fails.
  - E2E-P2.2-07 Claim validators: billing token with lifetime > 300 s rejected; feed token carrying `org` rejected.
  - E2E-P2.2-08 A production `ai-platform` bundle contains no testkit code (bundle scan).

---

## Phase P3 — AI Platform rework (05 §6.3 step 3)

### P3.1 — `VendorEntrypoint`, authorization classes, operator credentials and platform alerting
- **Spec** 065 · **Codebase** ai-platform · **Size** L · **Depends** P2.2 · **Parallel** P4.1, P1.x
- **Read:** 02 §1.3; 02 §3.3; 04 §1.1; 04 §1.3 (intro + rows register/revoke/listOperatorCredentials); 04 §1.5;
  03 §3.2 rows `operator_credential`, `assertion_used`, `control_audit`, `platform_alert`; 02 §5 (decision paragraph);
  04 §6.4 (vars Access/WebAuthn, `send_email`, observability).
- **Do not read:** coverage methods in 04 §1.3; 03 §6.
- **Code:** `src/worker.ts` (exports, `scheduled`, `Env`), `src/control/audit.ts`, `src/control/index.ts` (dispatch shape to mirror),
  `vitest.workers.config.ts`, `test/system/harness.ts`.
- **Implements:**
  - `VendorEntrypoint` (named `WorkerEntrypoint`) exported; one class table (M/H/HP) per method; `contract_version` checked on every argument object; results in the 04 §1.2 envelope.
  - Class H: forwarded Access JWT → actor email. Class HP: also the 04 §1.5 assertion rules (active credential, ≤ 5 min, single use via `assertion_used`, actor = Access email).
  - `operator_credential`: bootstrap only while the table is empty; register (HP, `pending` 24 h, `approved_by`); revoke (HP); `listOperatorCredentials` (M).
  - `control_audit` actor = Access email, plus `assertion_sha256`; every H/HP call audited.
  - `src/alert`: `platform_alert` dedupe/repeat/retry; `send_email` to the fixed destination (codes + ids + decoded operation);
    `*/5` cron branch (alert retry, heartbeat ping); AL-13 for credential bootstrap/register/revoke.
  - Observability on; JSON log lines; a failing scheduled job alerts. Platform clock module + test clock control (rule V4).
  - H-AP: self service binding to `VendorEntrypoint`, `vendorCall` helper, email and heartbeat capture, Access certs fixture (rule V2 step 1).
- **Out of scope:** issuer keys (→ P3.2), service keys and grants (→ P3.3), porting `/control/*` methods and removing them (→ P3.10), console ceremony (→ P4.7).
- **Outputs / freezes:** method dispatch + class table; auth refusal codes; credential lifecycle; alert body format; `platform_alert`.
- **E2E (H-AP via service binding):**
  - E2E-P3.1-01 Empty registry: bootstrap registration without approval → `pending`; AL-13 marked bootstrap; a second unapproved registration → `rejected`.
  - E2E-P3.1-02 HP call using a credential < 24 h old → rejected; after the test clock passes +24 h → `ok`.
  - E2E-P3.1-03 HP with a valid Access JWT + assertion over the exact operation → `ok`; replaying the same assertion → rejected (`assertion_used`).
  - E2E-P3.1-04 Assertion `issued_at` 6 min old → rejected; `actor_email` ≠ Access email → rejected.
  - E2E-P3.1-05 `revokeOperatorCredential` (class HP) with a missing, expired or wrong-`aud` Access JWT → `rejected` with code `unauthenticated`; no state change [TB-6, AD-11].
  - E2E-P3.1-06 Any method with `contract_version` missing or 2 → `rejected contract_version_unsupported`; nothing written.
  - E2E-P3.1-07 Credential A revokes B → HP with B fails; AL-13 sent [K-7 rotation].
  - E2E-P3.1-08 `send_email` throws → alert stays unsent; the next `*/5` run sends it exactly once [FM-16].
  - E2E-P3.1-09 `*/5` cron pings the heartbeat URL; a failing job inside it raises a platform alert.
  - E2E-P3.1-10 `listOperatorCredentials` returns only active credentials.

### P3.2 — Issuer tokens, issuer-key registry and tenant bindings
- **Spec** 066 · **Codebase** ai-platform · **Size** M · **Depends** P3.1 · **Parallel** P4.1
- **Read:** 02 §3.2; 04 §2.1; 03 §3.2 rows `issuer_key`, `tenant_binding`, `installation`; 04 §1.3 rows register/retire/revokeIssuerKey, listIssuerKeys;
  04 §6.1 rows identity, config-cache, discovery, journal (`authenticateGetRequest`), platform-vocabulary, control/lifecycle (enroll removal), control/token-contract;
  02 §6 row K-2; 05 §2 row AL-20.
- **Code:** `src/identity/index.ts:236-383`, `src/config-cache/index.ts`, `src/control/lifecycle.ts:201-467`, `migrations/20260731120000_platform_schema.sql`, `migrations/20260803120000_token_contract.sql`.
- **Implements:**
  - `issuer_key`; `registerIssuerKey`/`retireIssuerKey`/`revokeIssuerKey` (HP, AL-13); `listIssuerKeys` (M). `retireIssuerKey` is the only writer of `retiring`.
  - Issuer-token verifier replacing `EnrolledKeyVerifier`: `kid` active or retiring within validity, `iss = ISSUER_ID`, `aud` per route,
    lifetime ≤ 600 s, skew, `ver = "2"` via `token_contract` (insert 2, retire 1); existing replay rules.
  - `tenant_binding`: the first valid token for an unknown org creates installation + binding epoch 1; at most 50 creations per day
    across all tenants, then refusal + AL-20. `Principal.installationId` resolved through the binding.
  - Config-cache readers for `issuer_key` and `tenant_binding`; revocation effective within one cache TTL.
  - Drop `installation_key`, the enroll/rotate/revoke handlers and routes, and `INSTALLATION_KEY_TTL_DAYS`.
  - H-AP `newClinic()` (registers the test issuer key, mints issuer tokens); every suite that enrolls is migrated (rule V2 step 2).
    `/control/entitle` stays for admitting test clinics (transitional, rule S9).
- **Out of scope:** feed audience (→ P3.9); `/v1/coverage` role check (→ P3.9); `held_for_transfer` binding states (→ P3.8); removing entitlement (→ P3.10).
- **Outputs / freezes:** AI-token verification rules; `tenant_binding` model (epoch); issuer-key methods.
- **E2E (H-AP):**
  - E2E-P3.2-01 Token from a registered `kid` for a new org → authenticates; installation + binding epoch 1 created; a second token → same installation.
  - E2E-P3.2-02 Unknown `kid` → 401 `unauthenticated`; a `kid` revoked through HP → rejected after one cache TTL.
  - E2E-P3.2-03 `aud=abo` or `aud=ai-platform-feed`, lifetime 601 s, or `ver="1"` → 401 [TB-3].
  - E2E-P3.2-04 Two active `kid`s: tokens of both accepted; a retiring `kid` accepted until `not_after` [A13, K-2].
  - E2E-P3.2-05 51st new-org creation within 24 h → 401 `unauthenticated`; nothing created; AL-20.
  - E2E-P3.2-06 `GET /v1/requests/{ref}` with the owner org's token → 200; another org's token → not found.
  - E2E-P3.2-07 `/control/installations/*/enroll` → 404; no `installation_key` table.
  - E2E-P3.2-08 AL-13 on issuer-key registration carries the decoded operation and `kid`.

### P3.3 — Plan versions, paid-grant intake and the per-clinic coverage ledger
- **Spec** 067 · **Codebase** ai-platform · **Size** L · **Depends** P3.2 · **Parallel** P4.1
- **Read:** 03 §3.1 (`term`, `grant`, `outbox` rows; `hot` fields `binding_epoch`, `clinic_seq`, `next_alarm_at`); 03 §3.2 rows
  `service_key`, `plan_version`, `coverage_mirror`, `coverage_event`, `grant_ledger`; 03 §3.3; 03 §5.3; 03 §5.4 (first three placement rows);
  03 §6.1; 03 §6.7; 04 §1.3 rows grant (paid), getCoverage, readCoverageEvents, listGrants, register/revoke/listServiceKeys, publish/retirePlanVersion;
  04 §1.4; 04 §1.6 + §1.7.
- **Do not read:** 03 §6.2–§6.5 (→ P3.4, P3.5, P3.9).
- **Code:** `src/quota-do/index.ts` (blob state, `blockConcurrencyWhile`), `GatewayObject` in `src/worker.ts:1487-1561`, `wrangler.toml:17-19`.
- **Implements:**
  - DO SQLite tables `hot`/`term`/`grant`/`outbox`, migrated on first access (the old blob stays only for live admission until P3.4, rule S9).
    Worker→DO RPC carries `contract_version` (04 §7.1 row).
  - `service_key` (HP register/revoke + AL-13; M `listServiceKeys`); `PLATFORM_SIGNING_KEY` signs receipts (K-3).
  - `plan_version` publish/retire (HP), immutable once published.
  - `grant`, paid (M): validation steps 1–3 and the binding part of step 5 (resolve/create binding); `unknown_kid` → transient,
    revoked → `bad_signature`; idempotency (`already_applied` with the original receipt, `conflict`); placement active/queued; receipt.
  - `src/coverage/calendar.ts`: month/day arithmetic with end-of-month clamping, and `DURATION_SCALE`.
  - Outbox shipped by the DO alarm to `coverage_event` (`feed_seq`), `grant_ledger`, `coverage_mirror` (higher pair only), and R2 `grant-ledger/`;
    AL-11 on every grant (decoded operation); AL-17 paid-grant velocity.
  - `getCoverage`, `listGrants` (filters), `readCoverageEvents` (`after`, `limit ≤ 200`).
- **Out of scope:** admission against terms (→ P3.4); time boundaries and grace (→ P3.5); complimentary grants, ceilings, adjustments (→ P3.6);
  voids and tombstones (→ P3.7); transfer flags (→ P3.8); HTTP feed (→ P3.9).
- **Outputs / freezes:** `grant` (paid), `getCoverage`, `listGrants`, `readCoverageEvents`, service-key and plan-version methods; DO schema; event and receipt shapes.
- **E2E (H-AP via entrypoint; test clock + alarms):**
  - E2E-P3.3-01 Publish plan v1 (HP); paid grant (testkit ABO key) for a new org → `applied`; receipt verifies with the platform key; term active, `starts_at` = now.
  - E2E-P3.3-02 Same grant resent → `already_applied` with the identical receipt; one ledger row [NFR-02, NFR-03].
  - E2E-P3.3-03 Same `grant_id` with a changed allowance → `conflict`; nothing changes.
  - E2E-P3.3-04 Second paid grant → queued without dates; `getCoverage` shows `queued_count` 1 and `coverage_through` extended [FR-21].
  - E2E-P3.3-05 Unregistered signing `kid` → `transient unknown_kid`; revoked `kid` → `rejected bad_signature`.
  - E2E-P3.3-06 Refusals: unpublished plan → `plan_not_published`; allowance above max × months or grace 8 days → `exceeds_plan_bound`;
    paid unit `day` → `unit_not_allowed`; `placement=immediate` → `placement_not_supported` [AD-8 bound, X-06].
  - E2E-P3.3-07 After the alarm: `coverage_event` rows with rising `clinic_seq`, a `grant_ledger` row, `coverage_mirror` updated, an R2 object;
    `readCoverageEvents` pages in `feed_seq` order.
  - E2E-P3.3-08 AL-11 email per grant with the decoded operation + org; the 4th paid grant for one clinic within 24 h → AL-17.
  - E2E-P3.3-09 Grant at 31 Jan 10:00 → ends 28 Feb 10:00 (29 Feb in a leap year); with the staging `DURATION_SCALE`, a monthly term lasts 30 min.
  - E2E-P3.3-10 `retirePlanVersion` → the next grant on it is refused; the existing term keeps its snapshot.
  - E2E-P3.3-11 Platform Worker → per-clinic DO RPC with the current contract version → accepted; the answer echoes that `contract_version` [NFR-09].
  - E2E-P3.3-12 Platform Worker → per-clinic DO RPC with `contract_version` missing or unsupported (2 at launch) → `rejected` `contract_version_unsupported` with `accepted_versions`, before authentication and before any write; nothing changes [NFR-09].

### P3.4 — Admission and settlement against terms (live AI path)
- **Spec** 068 · **Codebase** ai-platform · **Size** L · **Depends** P3.3 · **Parallel** P4.1, P4.2
- **Read:** 03 §6.2; 03 §6.3; 03 §6.6 ("Normal operation" row); 03 §3.1 (`hot` row); 03 §3.2 rows `usage_event`, `usage_rollup`;
  04 §4.2 (rows `/v1/requests`, `/v1/capabilities`, and the denial-code table); 04 §6.1 rows quota-do, admission (not fallback),
  credit (`creditUsage`), entitlement, pipeline, capability, journal, rollup, dashboards, errors, adapter, soft-threshold, rate-limit, manifest,
  `worker.ts` (settlement, `periodFromIso`, cost class, `minimumPlanTier`); 04 §6.3 row usage_term.
- **Do not read:** 03 §6.4–§6.5; 04 §1.3.
- **Implements:**
  - DO admission steps 1–7 and settlement by reservation id; blob state removed; reservations older than 15 min charged; concurrency limit and capabilities from the plan snapshot.
  - Exhaustion and successor activation in the same transaction; band events at 75 % and 90 %, once per term per band.
  - Denial codes `allowance_exhausted`, `coverage_lapsed` + `coverage_reason`, `forbidden_capability`, `concurrency_limited` + `retry_after`
    (`suspended` mapped, and set in P3.6); `quota_exhausted` and `period_reset` removed; a DO `rejected` version answer → `coverage_unknown`.
  - Pipeline stages 3, 8 and 15 carry `term_id`, reservation and snapshot; cost class from the snapshot.
  - `usage_event.term_id` + unique `request_id` (insert-or-ignore); outbox `usage_adjustment`; rollup by `{installation_id, term_id}`; dashboards,
    rate-limit counters and soft-threshold on the new codes and band.
  - `/v1/capabilities` from `coverage_mirror` by primary key, never the TTL cache. Entitlement no longer read on the request path.
  - H-AP `coverClinic()` (paid grant over the entrypoint) replaces `entitleScenario`; every entitling suite migrated (rule V2 step 3).
- **Out of scope:** expiry, grace, alarms (→ P3.5); setting suspension (→ P3.6); fallback (→ P3.9); dropping entitlement tables and routes (→ P3.10); load and write budget (→ P3.11).
- **Outputs / freezes:** admission answer (reservation, `term_id`, snapshot, band); clinic denial codes of 04 §4.2. CP-B.
- **E2E (H-AP):**
  - E2E-P3.4-01 CP-B: paid grant → issuer token → `/v1/capabilities` lists the plan at once → `POST /v1/requests` completes → `usage_event` has `term_id`; `used` += w [NFR-05].
  - E2E-P3.4-02 Org never granted → 403 `coverage_lapsed` reason `none`; no journal row.
  - E2E-P3.4-03 Capability outside the plan → 403 `forbidden_capability`.
  - E2E-P3.4-04 17th concurrent in-flight request (limit 16 from the snapshot) → 429 `concurrency_limited` + `retry_after`, distinct from `rate_limited` [FR-09, P-11].
  - E2E-P3.4-05 A31: request reaching the allowance with nothing queued → term ends `exhausted`; next request `allowance_exhausted`; state `exhausted`; no grace.
  - E2E-P3.4-06 A32: with a queued term, exhaustion activates it at that instant with full allowance; `ends_at` = instant + 1 month.
  - E2E-P3.4-07 A34: two concurrent requests near the limit → one exhaustion event; overshoot ≤ w_max − 1; the other is charged to the successor or refused.
  - E2E-P3.4-08 Crossing 75 % and 90 % emits one band event each; no repeats [A29 platform half, FR-34].
  - E2E-P3.4-09 Provider consumed nothing → reservation released, `used` unchanged.
  - E2E-P3.4-10 Reservation unsettled > 15 min → charged at the next admission; the late settlement changes nothing; one `usage_event` (request_id dedupe) [NFR-06].
  - E2E-P3.4-11 Replayed `jti`/idempotency key → stored answer; no DO write.
  - E2E-P3.4-12 DO answers `rejected` (version) → client gets 503 `coverage_unknown`.

### P3.5 — Term boundaries, grace and renewal
- **Spec** 069 · **Codebase** ai-platform · **Size** M · **Depends** P3.4 · **Parallel** P4.2, P4.3
- **Read:** 03 §5.4 (rows queued→active, active `ends_at`, grace rows, grant during grace); 03 §5.7 (`grace`, `lapsed`); 03 §6.1 (end date, scale);
  03 §6.4; 03 §6.7 (alarm bullet); 03 §6.8; 05 §8 rows A9–A11.
- **Implements:** alarm at the next boundary (`setAlarm` only when it moves); boundary loop on alarm and on admission (step 3); expiry with a
  successor (`expired`, successor starts at the old `ends_at`); expiry → grace (`grace_ends_at`, `grace_base_used`, cap ⌈A × grace_days ÷ term days⌉);
  `grace_exhausted`; lapse; renewal during grace (calendar from the old `ends_at`, grace term ends `renewed`); no grace after exhaustion;
  scaled grace windows; mirror `hard_stop_at`.
- **Out of scope:** reversal ends (→ P3.7); fallback reads of `hard_stop_at` (→ P3.9).
- **Outputs / freezes:** clinic states `grace`/`lapsed` and reasons `expired`/`grace_exhausted` in the snapshot.
- **E2E (H-AP, test clock + `runDurableObjectAlarm`):**
  - E2E-P3.5-01 A9: renewal paid 5 days early queues; T1 allowance unchanged; at T1's end T2 is active with a full allowance from the old end date.
  - E2E-P3.5-02 A10: end date unpaid → grace; admitted within the cap; at `grace_ends_at` → lapsed, `coverage_lapsed reason expired`; no ABO in the harness.
  - E2E-P3.5-03 Grace cap consumed → `grace_exhausted`; refused with that reason [I-6].
  - E2E-P3.5-04 Grant on day 3 of grace → new term `calendar_start` = old `ends_at`; grace usage stays on T1 [I-5].
  - E2E-P3.5-05 A11: lapsed clinic paid 2 months later → new term starts now.
  - E2E-P3.5-06 Alarm suppressed → the next admission evaluates the boundary and refuses on time [FR-23, FM-12 catch-up].
  - E2E-P3.5-07 Staging `DURATION_SCALE`: monthly term 30 min, grace about 7 min, boundaries at the scaled times [NFR-07].
  - E2E-P3.5-08 Events for activate, end and grace start; mirror `hard_stop_at` = `ends_at` (active) or `grace_ends_at` (grace).

### P3.6 — Complimentary grants, ceilings, term adjustments and suspension
- **Spec** 070 · **Codebase** ai-platform · **Size** M · **Depends** P3.5 · **Parallel** P3.9, P4.x
- **Read:** 03 §5.3; 03 §3.2 row `ceiling_policy`; 04 §1.4 (validation step 4, rows `source`, `ceiling_override`, `adjustment`); 04 §1.3 rows grant (complimentary),
  grant `term_adjustment`, setCeilingPolicy, suspend, resume, inspectCoverage; 03 §6.1 (units, adjustments bullets); 05 §2 rows AL-11, AL-12, AL-19; 05 §8 rows A19, A20, A27.
- **Implements:** complimentary grant (HP; `month` or `day`; `operator_email` + `reason` required; assertion over the envelope); `ceiling_policy` (versioned,
  HP `setCeilingPolicy`), per-grant and 90-day-window checks counting adjustments; `ceiling_override` with a second, separate assertion + AL-12;
  `term_adjustment` (HP: plan change, added allowance, later end only; never queued terms); `suspend`/`resume` (H; DO flag; refused first; calendar runs; AL-19);
  `inspectCoverage` (H); the FR-92 pilot grant fits the default policy.
- **Out of scope:** voids (→ P3.7); console relays (→ P4.8).
- **Outputs / freezes:** complimentary and adjustment grant semantics; ceiling policy; `suspend`/`resume`/`inspectCoverage`.
- **E2E (H-AP):**
  - E2E-P3.6-01 A20: 14-day complimentary grant to a paying clinic → queued after current coverage; AL-11 marked for attention with operator + reason.
  - E2E-P3.6-02 A27: 365-day complimentary grant → `exceeds_ceiling`; with a valid override → `applied` + AL-12; reusing the first assertion as the override → rejected [SR-24].
  - E2E-P3.6-03 90-day window: 31 + 31 days accepted; a further 1 day → `exceeds_ceiling`; adjustment extensions counted.
  - E2E-P3.6-04 Missing `reason` or `operator_email` → rejected [FR-36].
  - E2E-P3.6-05 `term_adjustment`: +7 days moves `ends_at` later; shortening → rejected; a plan change shows in `/v1/capabilities` on the next call [FR-32].
  - E2E-P3.6-06 Suspend → 403 `suspended` before any other refusal; calendar keeps running; resume → admitted; AL-19 for both [FR-74, I-4].
  - E2E-P3.6-07 A19 platform half: 14-day trial grant, then a paid grant → paid term queues after the trial; no gap or overlap.
  - E2E-P3.6-08 `inspectCoverage` returns terms, grants and reservations; without an Access JWT → rejected.
  - E2E-P3.6-09 Pilot grant of 30 days (unit `day`) accepted under the default policy [FR-92].

### P3.7 — Reversal voids, tombstones, held terms and operator voids
- **Spec** 071 · **Codebase** ai-platform · **Size** M · **Depends** P3.6 · **Parallel** P3.9, P4.x
- **Read:** 03 §5.5; 03 §5.4 (rows: full reversal of the active/grace term, queued/held reversal, held release, grant voided); 03 §5.7 (`reversed`);
  03 §3.2 rows `grant_void`, `grant_ledger`; 03 §3.3 void object; 04 §1.3 rows voidForReversal, releaseHeld, voidGrant, listGrantsForVoid; 04 §1.4 step 5 (`voided`);
  05 §3.2 ("Compromise response" paragraph).
- **Implements:** `voidForReversal` (M, ABO-signed, idempotent by `reversal_id`) resolving the live term through `origin_grant_id`; effects `end_current`
  (no grace; queued → held), `remove_queued`, `none`; tombstone when the grant is not yet applied, so a later grant is `rejected voided`; partial voids rejected;
  `voidGrant` (HP); `releaseHeld` (HP; re-appended at the end); `listGrantsForVoid` (H; credential + window); `grant_void` in D1 and R2; `held_count`.
- **Out of scope:** lineage across a transfer (→ P3.8); deciding the effect on the ABO side (→ P4.5).
- **Outputs / freezes:** void, release and listing methods; the tombstone rule.
- **E2E (H-AP):**
  - E2E-P3.7-01 A15 platform half: void for the payment funding the active term, with T2 queued → T1 ends `reversed`, T2 held; refused `coverage_lapsed reason reversed`.
  - E2E-P3.7-02 Void for a queued term's payment → that term removed; active term unaffected.
  - E2E-P3.7-03 A17: void for an ended term → recorded only.
  - E2E-P3.7-04 Void before the grant → tombstone; the later grant with that id → `rejected voided`.
  - E2E-P3.7-05 `releaseHeld` → the held term is re-queued, and activates if nothing is active [I-3].
  - E2E-P3.7-06 `voidGrant` on an active complimentary term → ends `voided`; successor activates [SR-25].
  - E2E-P3.7-07 `listGrantsForVoid(credential, window)` lists exactly the grants made with that credential.
  - E2E-P3.7-08 Replayed `reversal_id` → `already_applied`; bad ABO signature → rejected; partial → rejected.
  - E2E-P3.7-09 `grant_void` rows, R2 objects and coverage events emitted.

### P3.8 — Transfer, deletion with coverage left, and ledger retention
- **Spec** 072 · **Codebase** ai-platform · **Size** L · **Depends** P3.7 · **Parallel** P3.9 (if not yet done), P4.x
- **Read:** 03 §5.4 (`transferred` rows + "Deletion with coverage left"); 03 §3.2 rows `tenant_binding`, `transfer`/`transfer_step`, `installation`;
  03 §4 (ordering-rule paragraph); 04 §1.2 (`ok` list and `transient` details); 04 §1.3 rows beginTransfer, transferOut/In, deleteInstallation; 04 §1.6 (transfer receipt); 03 §8 (platform rows);
  04 §6.1 rows retention, control/support-purge, control/lifecycle (delete); 05 §2 row AL-18.
- **Implements:** `beginTransfer` (HP: retire the source binding, new binding epoch + 1, new DO `awaiting_transfer`); `transferOut`/`transferIn` (M, idempotent by
  `transfer_id`) moving the package with `origin_grant_id`; the old DO is `transferred_out` and refuses grants; `deleteInstallation` (HP: no coverage → retire;
  coverage left → `held_for_transfer`, `transfer_pending` refusals, grants `transient`, no new binding, AL-18 daily); voiding the remaining grants retires the held
  binding; `voidForReversal` lineage across transfer; retention purge marks installations deleted and never touches ledgers, events, transfers or unended-term usage.
- **Out of scope:** the saga driver (→ P4.8); projection epoch handling (→ P5.2).
- **E2E (H-AP):**
  - E2E-P3.8-01 A14: active + queued clinic → `beginTransfer` → `transferOut` → `transferIn` → the new installation holds the terms with the same `origin_grant_id`s and remaining allowance; old answers `transferred`; AL-11 transfer; events carry epoch 2 [FR-72].
  - E2E-P3.8-02 Non-transfer grant during `awaiting_transfer` → `transient awaiting_transfer`; after `transferIn` it applies behind the moved terms.
  - E2E-P3.8-03 `transferOut`/`transferIn` retried → `already_applied`; `transferIn` before `transferOut` → `transient`.
  - E2E-P3.8-04 A24/FM-23: delete with paid time left → `held_for_transfer`; AI → `coverage_lapsed transfer_pending`; paid grant → `transient transfer_pending`; a new token creates no binding; AL-18; then `beginTransfer` from the held binding succeeds.
  - E2E-P3.8-05 Delete with no coverage → binding retired; the next token creates epoch 2.
  - E2E-P3.8-06 Held binding whose remaining grants are voided → retired; the next token → epoch + 1.
  - E2E-P3.8-07 `voidForReversal` for a paid grant moved by transfer → the effect lands on the new installation's term.
  - E2E-P3.8-08 Purge of a deleted installation → `grant_ledger`, `grant_void`, `coverage_event`, `transfer`, installation row and unended-term usage kept [RC-05, P-14].

### P3.9 — Fallback admission, coverage feed and administrator coverage read
- **Spec** 073 · **Codebase** ai-platform · **Size** M · **Depends** P3.5 · **Parallel** P3.6–P3.8 (rule S10), P4.x
- **Read:** 03 §6.5; 03 §6.6 (outage row); 03 §3.2 rows `fallback_admission`, `feed_consumer`, `coverage_mirror`; 03 §7 (Subscription reference row only); 04 §4.1 (first two paragraphs only);
  04 §4.2 rows `/v1/coverage`, `/v1/usage`; 04 §1.7 (companion-list bullets for `queued_terms` and `recent_terms` only); 04 §1.3 row feedConsumerHealth; 02 §3.2 (Feed row); 04 §6.1 rows admission (fallback), credit (reconcile), usage-summary, `worker.ts` (`*/5`).
- **Do not read:** 04 §4.1 backend pull cycle (→ P5.2).
- **Implements:** fallback when the DO errors or takes > 2 s: mirror by primary key, then the four conditions (state, not suspended, before `hard_stop_at`,
  capability, outage weight ≤ 5 × w_max); otherwise `coverage_unknown` + `retry_after`; `fallback_admission` rows with `request_id`; `*/5` drain with dedupe;
  `GRACE_ADMISSION_CAP` and `grace_admission_queue` removed. `GET /v1/feed/coverage` (feed token `aud=ai-platform-feed`, `sub=backend-feed`, no `org`;
  version header; pages; `feed_consumer` updated); `feedConsumerHealth` (M). `GET /v1/coverage` (administrator only: subscription ref, live DO snapshot read-only,
  queued terms, last 12 terms with usage). `/v1/usage` and `src/usage-summary` removed.
- **Out of scope:** backend puller (→ P5.2); desktop client (→ P6.2).
- **Outputs / freezes:** the HTTP feed contract; `/v1/coverage` response; `feedConsumerHealth`.
- **E2E (H-AP):**
  - E2E-P3.9-01 FM-06: DO forced to fail for an active clinic → admitted via fallback with a `fallback_admission` row; the DO recovers and `*/5` charges it once [P-12].
  - E2E-P3.9-02 Fallback weight beyond 5 × w_max → 503 `coverage_unknown` + `retry_after`.
  - E2E-P3.9-03 Fallback after `hard_stop_at` → `coverage_unknown` [FR-23].
  - E2E-P3.9-04 DO timed out after reserving → the drain skips that `request_id`; counted once.
  - E2E-P3.9-05 Feed pages with `after`/`limit`/`next_after`/`has_more`; a feed token on `/v1/requests` → 401; an AI token on the feed → 401; `feedConsumerHealth` shows the last pull.
  - E2E-P3.9-06 Feed without, or with an unsupported, version → 400 `contract_version_unsupported`.
  - E2E-P3.9-07 `/v1/coverage` as administrator → snapshot, queued, last 12 terms; staff token → 403; no DO write [FR-60, FR-61].
  - E2E-P3.9-08 `GET /v1/usage` → 404.

### P3.10 — Control-plane port to `VendorEntrypoint` and removal of `/control/*`
- **Spec** 074 · **Codebase** ai-platform · **Size** L · **Depends** P3.8, P3.9 · **Parallel** P4.x
- **Read:** 04 §1.3 (rows kill switch … token contract, supportLookup, and the "Removed" paragraph); 04 §6.1 rows `src/control/*` (all), support, `worker.ts`
  (`/control` dispatch, `Env`); 04 §6.3 rows drop_invoicing and the drop clauses of coverage_ledger; 04 §6.4; 04 §6.5; 02 §3.1 ("Removed" paragraph); 02 §1.4 (last paragraph).
- **Implements:** H methods for kill switches, routing policy (publish/canary/promote/rollback), cohort (plan membership from `plan_version`), capability lifecycle,
  token contract; `supportLookup` by reference, subscription ref and org; AL-19 on kill-switch changes. Delete the `/control/*` dispatch, auth, http, entitle,
  credit-price, the old plan CRUD, quota-inspect, period-close and invoice code; drop the `invoice`, `credit_price`, `plan` and `entitlement` tables;
  remove `OPERATOR_BEARER_TOKEN`/`OPERATOR_ID`. Final wrangler: `workers_dev=false`, `preview_urls=false`, crons (`0 5 1 * *` removed), vars. **Completes the
  harness migration (rule V2 step 4):** `operatorFetch` deleted; `test/e2e/harness/control.ts` and `env.ts` rewritten; suites deleted or rewritten per 04 §6.5;
  vitest configs without the bearer binding.
- **Out of scope:** viewer and `docs/testing/catalog` (→ P7.1); console UI (→ P4.9).
- **E2E (H-AP + e2e catalog):**
  - E2E-P3.10-01 Every former `/control/*` path → 404; the worker boots without `OPERATOR_BEARER_TOKEN` [FR-91, P-07].
  - E2E-P3.10-02 Routing policy publish → canary → promote over the entrypoint; traffic follows (port of SYS suite 4).
  - E2E-P3.10-03 Kill switch on a capability → `capability_disabled`; AL-19; audit actor = Access email.
  - E2E-P3.10-04 Capability deprecate/retire over the entrypoint → discovery reflects it.
  - E2E-P3.10-05 Token-contract rotation over the entrypoint (ver 2 current).
  - E2E-P3.10-06 `supportLookup` by subscription ref → that clinic's requests; by reference → envelope within retention.
  - E2E-P3.10-07 Crons: `0 5 1 * *` gone; `0 3`/`0 4` run retention and rollup keyed by `term_id`.
  - E2E-P3.10-08 The full rewritten SYS and e2e catalogue is green, with no bearer token anywhere in the test config.

### P3.11 — Platform rebuild procedures and the write budget
- **Spec** 075 · **Codebase** ai-platform · **Size** M · **Depends** P3.10 · **Parallel** P4.x
- **Read:** 05 §5.2; 05 §5.3; 01 §7 row R-7; 03 §6.6; 03 §6.7 (write-budget bullet); 04 §6.5 ("Add" row, concurrency test).
- **Implements:** an H method that emits a fresh snapshot event per installation (rebuilds `coverage_mirror`); a DO rebuild (H) from the last `coverage_event` plus
  later ledger, void and hold/suspension/transfer events, plus `usage_event` by `term_id`, compared with the mirror; a D1 rebuild of `grant_ledger`/`grant_void`
  from R2 `grant-ledger/`; a load scenario for A34 measuring DO rows written per AI request against about 2 (R-7).
- **E2E (H-AP + load suite):**
  - E2E-P3.11-01 FM-20: wipe a clinic's DO storage → rebuild → terms, positions, holds and usage equal the pre-loss state (in-flight reservations forfeited); compare clean.
  - E2E-P3.11-02 A rebuild that diverges from the mirror → platform alert.
  - E2E-P3.11-03 `grant_ledger` truncated → rebuilt from R2, identical.
  - E2E-P3.11-04 Snapshot refresh → one new `coverage_event` per installation; mirror updated.
  - E2E-P3.11-05 Load: 100 concurrent requests across exhaustion → one exhaustion; overshoot ≤ w_max − 1; ≤ 2 DO row writes per request [A34, R-7].

---

## Phase P4 — ABO (05 §6.3 step 4)

**Goal.** Build the ABO Worker: offers, checkouts, the Paymob adapter, the work pipeline, the ledger copy and the operator
console (02 §1.2, 03 §2). P4.1 starts alongside P3.1; later units join the platform only through methods that are already
frozen, and always call the real platform worker over the service binding (rules S7 and S10).

### P4.1 — ABO skeleton, records layer, billing-token auth and catalogue reads
- **Spec** 076 · **Codebase** `abo/` (new) · **Size** L · **Depends** P2.2 · **Parallel** P3.1–P3.3, P1.x
- **Read:** 02 §1.2 (module table); 02 §1.4; 03 §2.1; 03 §2.2; 03 §2.3 (table + first two sentences; not erasure); 04 §2.2 (rows `GET /v1/offers`,
  `GET`/`PUT /v1/billing-contact`, and Rules); 04 §2.3; 05 §2 row AL-16 + 02 §5 (decision paragraph).
- **Do not read:** 03 §2.4–§2.11, 04 §5.
- **Code:** `ai-platform/wrangler.toml` and `ai-platform/test/system/harness.ts` as patterns only.
- **Implements:**
  - `abo/` Worker: wrangler with D1, R2, `send_email`, crons (minute, hourly, 6-hourly, daily 06:00 declared), `workers_dev=false`, `preview_urls=false`,
    observability; module folders per 02 §1.2 (code only where used).
  - Hostname routing: the billing host serves `/v1`, `/notify`, `/return`; the ops host serves `/ops` only; cross-host requests rejected.
  - `Abo-Contract-Version` checked before auth on `/v1` and `/ops`; error body `{code, message, contract_version}` with the 04 §2.3 codes.
  - Billing-token verification against the pinned `ISSUER_KEYS` (several `kid`s): `aud=abo`, `ver`, ≤ 300 s, `role=administrator`; tenant only from `org`; 60 requests per token.
  - Records: ULIDs, append-only triggers, `fact_log`, `fact_export`; minute-cron exporter to R2 `ledger/` (NDJSON per fact, no contact values); AL-16 (export > 1 h behind; daily R2 lock check).
  - Tables `offer`, `offer_version`, `offer_event`, `terms_version`, `billing_contact`; `GET /v1/offers` (sellable latest versions + terms text from R2);
    `GET`/`PUT /v1/billing-contact` (versioned, idempotent by `client_request_id`, E.164).
  - Alert engine (`alert` dedupe, repeat, send, retry) + heartbeat ping on the minute cron; ABO clock module + test clock; H-ABO harness; ABO CI job.
- **Out of scope:** checkouts (→ P4.2); offer publication (→ P4.7; seeded by D1 fixture until then); erasure (→ P4.7); console (→ P4.6).
- **Outputs / freezes:** ABO clinic-API envelope, auth and error rules; records conventions; alert engine; H-ABO.
- **E2E (H-ABO):**
  - E2E-P4.1-01 No `Abo-Contract-Version` (with an invalid token) → 400 `contract_version_unsupported` before auth.
  - E2E-P4.1-02 AI token (`aud=ai-platform`) → 401; billing token signed by an unpinned `kid` → 401; `role=doctor` → 403 `forbidden_role` [TB-2, FR-10].
  - E2E-P4.1-03 `GET /v1/offers` lists only the sellable latest versions with terms text; a retired offer is absent [A21, A33 listing].
  - E2E-P4.1-04 `PUT` contact twice with the same `client_request_id` → one version; a new request → version 2; invalid phone → 422 `invalid_request` [FR-51].
  - E2E-P4.1-05 Tenant B's token never sees A's contact; an `org` in the body is ignored [SR-03].
  - E2E-P4.1-06 `/ops/*` on the billing host and `/v1/*` on the ops host → rejected [02 §1.4].
  - E2E-P4.1-07 UPDATE/DELETE on an append-only table aborts; each fact has a `fact_log` row; the minute cron writes NDJSON under `ledger/` in `fact_seq` order with no contact values [RC-01, RC-03].
  - E2E-P4.1-08 Export stalled > 1 h → AL-16 once, then daily; `send_email` failure retried [FM-16].
  - E2E-P4.1-09 61st request within one token's life → 429 `rate_limited`.
  - E2E-P4.1-10 Minute cron pings the heartbeat URL.

### P4.2 — Checkout creation, Paymob intention, coverage view and the cross-worker harness
- **Spec** 077 · **Codebase** abo · **Size** L · **Depends** P4.1, P3.3 · **Parallel** P3.4–P3.6
- **Read:** 03 §2.4; 03 §2.11 (row `paymob_intention`); 03 §5.1 (diagram + shown-state table); 04 §2.2 (rows `POST /v1/checkouts`, `GET /v1/checkouts/{id}`,
  `GET /v1/checkouts?open=1`, Rules); 04 §5.1 (rows capabilities, createCheckout, cancelCheckout); 04 §5.3 (row createCheckout); 03 §2.10 rows `coverage_view`,
  `feed_cursor` + 03 §4 ordering rule; 05 §6.1 ("Inquiry stub" bullet).
- **Implements:**
  - Provider port + registry (`provider_id`); Paymob adapter `createCheckout` (intention API, piastres, EGP, 1800 s, `special_reference`, notify URL, `return_url` with `v`),
    `capabilities`, `cancelCheckout` = `unsupported`; `paymob_intention`. R-2 (expiry default) recorded. Import-boundary CI check: only the adapter imports provider code [G6].
  - `POST /v1/checkouts`: needs a contact, current terms and the current sellable `offer_version`; snapshot; `opened_with_coverage_through` from a live `getCoverage`,
    falling back to `coverage_view` (`coverage_source=view`); `starts` = `now` or `after_current` + `projected_start`; provider refusal → `open_failed` + 503;
    idempotent by `client_request_id`; 10 per tenant per hour; `jti` stored.
  - `GET /v1/checkouts/{id}` (Waiting/Abandoned at this stage) and `GET /v1/checkouts?open=1`.
  - `coverage_view` + `feed_cursor` via `readCoverageEvents` on the minute cron, using the ordering rule.
  - H-PAY stub (intention + auth endpoints) and **H-XW** (real ai-platform as an auxiliary worker bound to `VendorEntrypoint`; build script; CI job).
- **Out of scope:** notifications and confirmation (→ P4.3); expiry sweeps (→ P4.5); operator cancel (→ P4.6).
- **Outputs / freezes:** checkout API; provider-port interface; H-PAY and H-XW harnesses.
- **E2E (H-XW + H-PAY):**
  - E2E-P4.2-01 Admin with contact and terms → 201 with `redirect_url`, `CK-…` reference, `expires_at` = +30 min; the stub received piastres and `special_reference` = reference [FR-11].
  - E2E-P4.2-02 A30: clinic with active coverage on the real platform → `starts=after_current`, `projected_start` = `coverage_through` [FR-30, FR-31].
  - E2E-P4.2-03 FM-22: platform binding throws → checkout still created, `coverage_source=view`.
  - E2E-P4.2-04 Superseded `offer_version` → 409 `offer_unavailable` + current version [A8, A21]; no contact → `billing_contact_required`; stale terms → `terms_not_accepted`.
  - E2E-P4.2-05 FM-09: stub refuses or times out → 503 `provider_unavailable`; `open_failed` event; shown Abandoned.
  - E2E-P4.2-06 Same `client_request_id` → same checkout; 11th in an hour → 429.
  - E2E-P4.2-07 A22: admin B gets A's checkout id → 404; two open A checkouts both listed in `?open=1` [FR-15, SR-04].
  - E2E-P4.2-08 After platform grant events, the minute cron updates `coverage_view`; an older `(epoch, seq)` is ignored.
  - E2E-P4.2-09 Import-boundary check fails on a fixture where a domain module imports adapter code [G6].

### P4.3 — Notification intake, inquiry, work pipeline and payment confirmation
- **Spec** 078 · **Codebase** abo · **Size** L · **Depends** P4.2 · **Parallel** P3.5–P3.7
- **Read:** 03 §2.5; 03 §2.6; 03 §2.9; 03 §2.11 (rows `paymob_txn`, `paymob_state_seen`); 03 §5.2 (classification bullets); 03 §5.6; 04 §5.1 (rows parseNotification, inquire) + 04 §5.2;
  04 §5.3 (rows parseNotification, inquire, order binding, normalisation, `payment_id` input); 05 §6.1 ("HMAC replay fixture" bullet).
- **Do not read:** 03 §2.7, §5.5 (→ P4.5).
- **Implements:**
  - `POST /notify/paymob`: body cap, rate limit, HMAC-SHA512 over the 20 fields in constant time; evidence to R2 `evidence/` + `notification` + `confirm` work row in one D1 batch;
    invalid-HMAC counter + ≤ 10 samples per hour (30-day prefix); AL-02; state dedupe key [SR-02]. `GET` response callback and `GET /return/paymob` (any `v`) only schedule an inquiry.
  - Work-row framework: lease by conditional update, backoff 1 → 15 min, `parked`, inline `waitUntil` + minute cron (≤ 50 rows); AL-01 for rows open > 5 min.
  - Confirm step: `inquire` (cached auth token; order inquiry / transaction lookup), `bound` check, normalisation, `payment_id` in the adapter, payment fact
    (classification `normal`/`likely_duplicate`/`late`, disposition `grant`/`withheld_mismatch`/`reversed_before_grant`), checkout events, `inquiry_result` only on change,
    `adapter_version` on evidence; AL-05, AL-09; the `grant` work row inserted in the same batch (consumed by P4.4). R-2 spike recorded.
  - H-PAY: inquiry endpoints + recorded callback fixture.
- **Out of scope:** grant call (→ P4.4); sweeps, expiry, reversals (→ P4.5).
- **E2E (H-ABO + H-PAY):**
  - E2E-P4.3-01 Replayed success callback re-signed → notification stored; inquiry bound success → `PAY-…` payment; checkout `paid`; `grant` row open [FR-12, SR-01].
  - E2E-P4.3-02 Same body again → disposition `duplicate`; still one payment [NFR-02].
  - E2E-P4.3-03 Bad HMAC → nothing stored as evidence; 3 within 15 min → AL-02; a sample kept [TB-1, A23].
  - E2E-P4.3-04 A5: decline callback, then a success on the same checkout → `attempt_declined`, checkout still open, then one payment.
  - E2E-P4.3-05 Unbound order (different order id) → no payment + alert; amount mismatch → `withheld_mismatch`, no grant row, AL-05 [FR-13, FR-16, A7].
  - E2E-P4.3-06 First inquiry already shows a refund → `reversed_before_grant`; no grant [FR-42].
  - E2E-P4.3-07 A6: second payment from a checkout opened at the same `opened_with_coverage_through` → `likely_duplicate` + AL-09; disposition still `grant` [FR-41].
  - E2E-P4.3-08 Inquiry timeout or rate limit → row stays open with backoff, succeeds later; open > 5 min → AL-01 [NFR-01].
  - E2E-P4.3-09 FM-08: R2 write fails → 5xx to the callback; nothing enqueued.
  - E2E-P4.3-10 FM-21: forced batch failure → no facts, row retried; FM-15: two runners → one lease wins.
  - E2E-P4.3-11 `GET /return/paymob?v=99` → neutral page, inquiry scheduled [04 §7.1].
  - E2E-P4.3-12 Authentic response callback (GET) → schedules an inquiry only.

### P4.4 — Grant pipeline to the platform: purchase to AI on
- **Spec** 079 · **Codebase** abo · **Size** M · **Depends** P4.3, P3.4 · **Parallel** P3.6–P3.8
- **Read:** 03 §2.8; 02 §1.5 (first diagram); 04 §1.2; 04 §1.3 rows grant, listServiceKeys; 04 §1.4 (field table only); 04 §1.6; 02 §6 rows K-3, K-4;
  05 §2 rows AL-04, AL-07, AL-23; 04 §2.2 rows `GET /v1/subscription`, `GET /v1/payments`.
- **Implements:** grant step (envelope from the payment and checkout snapshot, `grant_id = H(payment_id)`, signed with the current ABO `kid` on each attempt) → platform `grant`;
  outcomes: applied/already_applied → `grant_outcome` + receipt checked against the configured platform public keys; `transient` → backoff forever;
  `conflict`/`rejected` → parked + AL-07; AL-04 after 5 min of transient or unreachable; AL-23 self-check at isolate start and hourly (`listServiceKeys`), pausing
  grant/reverse work; shown state Active; `GET /v1/subscription` (subscription ref, snapshot, notices `duplicate_payment`, `late_payment_honoured`, `payment_withheld`);
  `GET /v1/payments` (cursor pages).
- **Out of scope:** reversal notices (→ P4.5); operator retry (→ P4.6).
- **Outputs / freezes:** subscription and payments responses. CP-C.
- **E2E (H-XW + H-PAY):**
  - E2E-P4.4-01 CP-C / A1 local: checkout → callback → confirm → grant → platform term active with full allowance → issuer AI token → `POST /v1/requests` completes;
    the checkout shows Active; the payment is in `/v1/payments`; run for 1, 3 and 12 months [G1, FR-12].
  - E2E-P4.4-02 A4/FM-04: platform answers `transient` for 4 days (test clock) → retries at ≤ 15 min; AL-04 hourly; then applied; term starts at activation [I-2].
  - E2E-P4.4-03 FM-05: platform `rejected` → parked + AL-07; never retried automatically.
  - E2E-P4.4-04 Outcome lost after the call (crash) → retry answers `already_applied` with the same receipt; one term [FM-13 partial].
  - E2E-P4.4-05 A6: two payments → the second term is queued on the platform; `/v1/subscription` shows `duplicate_payment`.
  - E2E-P4.4-06 FM-24/AL-23: the ABO `kid` is not registered → grant work paused (not parked) + AL-23; after registration it resumes.
  - E2E-P4.4-07 K-3 rotation: the platform switches to a second configured `kid` → receipts accepted; grants continue.
  - E2E-P4.4-08 A2: no clinic API call after checkout creation → still provisioned; a later `?open=1` shows Active.
  - E2E-P4.4-09 `/v1/payments` cursor pages; tenant B sees none of A's payments [A36 ABO half].

### P4.5 — Sweeps, reversals and the inquiry budget
- **Spec** 080 · **Codebase** abo · **Size** L · **Depends** P4.4, P3.7 · **Parallel** P3.8–P3.10
- **Read:** 03 §2.7; 03 §5.1 (expired/late edges); 03 §5.2 (reversal edges); 03 §5.5; 05 §1 (ABO rows: minute sweeps, hourly, 6-hourly, daily; budget sentence);
  04 §1.3 row voidForReversal; 05 §2 rows AL-03, AL-06, AL-08; 05 §8 rows A3, A16, A17, A23.
- **Implements:** checkout sweeps (+2, +5, +10, +20 min, every 10 min to expiry, a final inquiry → `expired`, widening to 7 days for expired/cancelled); late payment →
  `paid_late`, classification `late`, AL-08; AL-03 (confirmed with no verified callback); reversals from notifications (parent flags, child transaction) and tiered inquiries
  (hourly in the first 7 days or while the grant is unapplied; 6-hourly while funding a live, queued or held term; daily one-seventh up to 180 days); `reversal` facts
  (cumulative, `is_full`), dismissal + finding; effect (`tombstone`, `end_current`, `remove_queued`, `none`, `review_partial`); `reverse` work rows → signed
  `voidForReversal`; `reversal_outcome`; AL-06 on every reversal; per-minute inquiry budget with confirm/grant first; notices `reversal_recorded`, `terms_held`.
- **Out of scope:** manual chargeback (→ P4.7); `unrecorded_reversal` from payouts (→ P4.10).
- **E2E (H-XW + H-PAY):**
  - E2E-P4.5-01 A3/FM-02: callback blocked → the +2 min sweep inquires → payment → grant; AL-03.
  - E2E-P4.5-02 A23/FM-03/FM-18: every callback fails HMAC → AL-02, and sweeps still confirm the payments.
  - E2E-P4.5-03 Unpaid past expiry → final inquiry → `expired`; payment on day 3 → `paid_late`, `late`, granted at the snapshot, AL-08 [G3].
  - E2E-P4.5-04 A16: parent-flag refund on the payment funding the active term → a reversal (never a payment), `end_current` → platform void → term reversed, queued held; AL-06; notice `terms_held` [FR-43].
  - E2E-P4.5-05 A16: child-transaction refund → same result; the dedupe key prevents a double reversal [SR-02].
  - E2E-P4.5-06 A17: reversal of a payment whose term ended → effect `none`; recorded + AL-06.
  - E2E-P4.5-07 Full reversal while the grant is granting or parked → tombstone; the pending grant is later `rejected voided`; its work row closes.
  - E2E-P4.5-08 Partial refund → `review_partial`; no void; alert [X-01].
  - E2E-P4.5-09 Lost refund callback found by the hourly tier (day 3), the 6-hour tier (live term) and the daily tier (100-day-old payment) [FR-82].
  - E2E-P4.5-10 More due inquiries than the per-minute budget → confirm and grant rows served first; none dropped.
  - E2E-P4.5-11 Inquiry contradicts a refund callback → reversal dismissed + finding.

### P4.6 — Operator console: Access perimeter, lookup, views and class-H ABO actions
- **Spec** 081 · **Codebase** abo · **Size** M · **Depends** P4.5, P3.6 · **Parallel** P3.9–P3.11
- **Read:** 05 §3.1; 05 §3.2 (rows "Retry parked work", "Cancel an open checkout", and the sentence after the table); 02 §2 row TB-7; 02 §3.1 row K-8;
  03 §2.10 row `operator_action`; 04 §7.1 row "ABO console".
- **Implements:** `/ops/*` on the ops host with Access JWT validation in the Worker (package); console pages served by the ABO; lookup by subscription ref, `org_id`,
  billing email, `CK-`/`PAY-`/`GR-` refs; clinic page (`inspectCoverage` forwarded with the operator's Access JWT; checkouts + events, payments, reversals, grant
  requests + receipts, operator actions, findings, alerts); global views (parked work, open findings, recent grants by source and credential via `listGrants`,
  payout imports, key and credential registries); H actions retry-parked and cancel-checkout; `operator_action` with actor email + `access_jti`; version header + reload prompt.
- **Out of scope:** passkey ceremony and HP actions (→ P4.7–P4.9); findings content (→ P4.10).
- **E2E (H-XW, console HTTP):**
  - E2E-P4.6-01 Ops host without, or with an expired or wrong-`aud`, Access JWT → rejected [SR-22, TB-7].
  - E2E-P4.6-02 Lookup by `AIC-…` → the clinic page shows platform terms (`inspectCoverage`) and ABO checkouts and payments [FR-70].
  - E2E-P4.6-03 Lookup by billing email and by `PAY-` ref reaches the same clinic.
  - E2E-P4.6-04 Parked grant → retry → open → applied after the cause is fixed; `operator_action` recorded [FR-71, FM-05].
  - E2E-P4.6-05 Cancel an open checkout → `cancelled`; a later payment → `paid_late` (sweeps continue).
  - E2E-P4.6-06 Stale `Abo-Contract-Version` from the console → `contract_version_unsupported` → reload state.
  - E2E-P4.6-07 `inspectCoverage` relay carries the operator's Access JWT; the platform audits the actor email [FR-73].

---

### P4.7 — Console passkey ceremony and ABO-side HP actions
- **Spec** 082 · **Codebase** abo · **Size** M · **Depends** P4.6, P3.1 · **Parallel** P3.10–P3.11
- **Read:** 02 §3.3 (last paragraph); 04 §1.5; 05 §3.2 (rows manual chargeback, release withheld, publish/retire offer or terms, erase contact data);
  03 §2.2 ("sellable" paragraph); 03 §2.3 (erasure paragraph); 03 §2.6 (row `payment_release`); 04 §1.3 row listOperatorCredentials.
- **Implements:** WebAuthn `get` ceremony in the console, building the operation object with the package; ABO-side HP verification against the platform's
  `listOperatorCredentials` (cached and refreshed) plus freshness and single use; actions: publish, retire and reinstate offer versions and terms versions
  (`offer_event`, terms text in R2, `assertion_sha256`); release a withheld payment (refused when fully reversed) → grant request; manual chargeback
  (`source=operator`, `detected_via=manual`) → the P4.5 effect pipeline; erase a tenant's contact data (blank every version, `erased_at`, delete raw R2 bodies, keep hashes).
- **Out of scope:** relays of platform HP actions (→ P4.8, P4.9).
- **E2E (H-XW):**
  - E2E-P4.7-01 Publish offer v2 (new price) with a passkey → `/v1/offers` shows v2; an open v1 checkout is still charged and granted at v1 [A8, FR-04].
  - E2E-P4.7-02 Retire an offer → gone from `/v1/offers`; a checkout on it → `offer_unavailable`; existing platform terms unchanged [A21, A33].
  - E2E-P4.7-03 HP action with no assertion, an assertion over a different operation, or a stale one → refused; `operator_action` records the result.
  - E2E-P4.7-04 Release a withheld payment → grant applied; releasing a fully reversed payment → refused [FR-16].
  - E2E-P4.7-05 A15: manual chargeback on the payment funding the current term → void → term reversed, queued held; AL-06 [FR-44].
  - E2E-P4.7-06 Erasure → contact fields blank in all versions; R2 evidence bodies deleted; D1 hashes and the ledger export intact; the next checkout → `billing_contact_required` [R-9].
  - E2E-P4.7-07 Credential revoked on the platform → the ABO refuses HP with it after refresh.

### P4.8 — Console relays: complimentary grants, adjustments, voids, suspension, deletion and the transfer saga
- **Spec** 083 · **Codebase** abo · **Size** M · **Depends** P4.7, P3.8 · **Parallel** P3.10–P3.11
- **Read:** 05 §3.2 (rows suspend/resume, complimentary/adjustment, ceiling override, transfer/release/void, delete) + "Compromise response"; 04 §1.3 rows grant (complimentary),
  term_adjustment, beginTransfer, transferOut/In, releaseHeld, voidGrant, listGrantsForVoid, suspend, resume, deleteInstallation; 03 §2.8; 03 §7 (`grant_id` comp/transfer forms).
- **Implements:** console forms and relays (Access JWT + assertion forwarded; the platform verifies) for complimentary grants (`grant_request` with
  `grant_id` from the operator action id), term adjustments, ceiling override (second assertion), suspend/resume (H), `releaseHeld`, `voidGrant`, `listGrantsForVoid`
  → void flow, `deleteInstallation`, `beginTransfer` → `transfer_step` work rows driving `transferOut`/`transferIn` until both are applied; transfer grant
  requests recorded; one `operator_action` per action.
- **E2E (H-XW):**
  - E2E-P4.8-01 A20 via the console: 14-day extension → applied; AL-11; `operator_action` and `grant_request` linked [FR-35].
  - E2E-P4.8-02 A27: 365-day grant → `exceeds_ceiling` shown; with an override (second passkey) → applied + AL-12.
  - E2E-P4.8-03 A19: trial grant, then the clinic buys through the clinic API → the paid term queues after the trial [FR-37].
  - E2E-P4.8-04 A14: `beginTransfer` → saga steps retried through `transient` until both applied; the clinic page shows epoch 2 [FR-72].
  - E2E-P4.8-05 A24: delete with time left → held; then a transfer from the held binding.
  - E2E-P4.8-06 SR-25 drill: credential Y revokes X; list X's grants in a window; void each → terms end `voided`.
  - E2E-P4.8-07 Suspend from the console → the clinic is refused `suspended`; resume restores it [FR-74].
  - E2E-P4.8-08 Simulated compromised ABO forwards an HP relay without an assertion → the platform rejects it [TB-6, SR-21].

### P4.9 — Console relays: platform configuration, registries and bootstrap
- **Spec** 084 · **Codebase** abo · **Size** M · **Depends** P4.7, P3.10 · **Parallel** P4.8 (different files), P5.x
- **Read:** 05 §3.2 (rows kill switches/routing, plan version/ceiling policy, register/retire/revoke keys and credentials); 04 §1.3 rows kill switch…token contract,
  supportLookup, publish/retirePlanVersion, setCeilingPolicy, register/retire/revokeIssuerKey, register/revoke service keys, register/revokeOperatorCredential; 02 §6 (table); 04 §6.6 (bootstrap script row).
- **Implements:** console pages for plan-version publish/retire, ceiling policy, issuer-key register/retire/revoke and service-key register/revoke, operator credential bootstrap and
  registration (WebAuthn `create` → attestation + approving assertion) and revocation, kill switches, routing policy (publish/canary/promote/rollback, replacing
  `bootstrap-routing-policy.sh`), cohort, capability lifecycle, token contract, support lookup by reference.
- **E2E (H-XW):**
  - E2E-P4.9-01 First run: empty registry → console bootstrap registration → AL-13 bootstrap; a second credential approved by the first → pending 24 h.
  - E2E-P4.9-02 Publish a plan version in the console → a paid grant on it is accepted [FR-01].
  - E2E-P4.9-03 K-2 drill: register a new issuer `kid` → AI tokens with it accepted; revoke → rejected within the TTL [SR-11].
  - E2E-P4.9-04 K-4 drill: register the next ABO service key and switch the ABO secret → grants continue; revoke the old one; AL-23 stays clear.
  - E2E-P4.9-05 Routing policy seeded from the console → requests routed to the fake provider.
  - E2E-P4.9-06 Kill switch from the console → `capability_disabled` + AL-19.
  - E2E-P4.9-07 Support lookup by request reference shows the envelope; audited with the actor email.

### P4.10 — Reconciliation, payout import and findings
- **Spec** 085 · **Codebase** abo · **Size** M · **Depends** P4.8 · **Parallel** P4.9, P5.x
- **Read:** 05 §3.3; 03 §2.10 rows `finding`, `finding_resolution`, `payout_import`, `payout_line`; 04 §5.1 + §5.3 rows payoutLines; 05 §3.2 row "Import a payout CSV; resolve a finding";
  05 §2 row AL-10; 05 §10 row FR-80.
- **Implements:** reconciliation daily and after each import, with all ten 05 §3.3 checks; `finding` + AL-10 (daily); H resolve-finding; payout CSV import
  (H; file to R2 + SHA; lines parsed by the adapter; transaction ids mapped via `paymob_txn`); `feed_divergence` compares `coverage_view` with `getCoverage` for
  clinics with events in the last day. H-PAY payout CSV fixtures.
- **E2E (H-XW + H-PAY):**
  - E2E-P4.10-01 A clean month (payments, grants, complimentary grants, a transfer) → zero findings [FR-81].
  - E2E-P4.10-02 AD-8: paid grant applied on the platform with the testkit ABO key and no ABO payment → `grant_without_payment` + AL-10.
  - E2E-P4.10-03 Complimentary platform grant with no ABO `operator_action` → `grant_without_operator_action`; transfer without one → `transfer_without_authorisation`.
  - E2E-P4.10-04 Grant parked > 15 min → `payment_without_grant`.
  - E2E-P4.10-05 A18: payout CSV with an unrecorded chargeback → `unrecorded_reversal`; manual chargeback (P4.7) → access ends; re-run clean.
  - E2E-P4.10-06 Amount mismatch → `payout_unmatched`; a missing settled payment → `payment_not_in_payout`.
  - E2E-P4.10-07 HMAC-valid success never confirmed → `callback_without_confirmation`.
  - E2E-P4.10-08 Tampered `coverage_view` → `feed_divergence`; full reversal without a void receipt → `reversal_not_applied`.
  - E2E-P4.10-09 AD-15: stored receipt that differs from `listGrants` → finding.

### P4.11 — Daily digest, platform watch, housekeeping and ABO rebuild
- **Spec** 086 · **Codebase** abo · **Size** M · **Depends** P4.10, P3.9 · **Parallel** P5.x
- **Read:** 05 §3.4; 05 §1 (ABO hourly and daily rows); 05 §2 rows AL-14, AL-15, AL-22; 05 §5.1; 03 §8 (rows: completed work rows, invalid-HMAC samples); 04 §1.3 rows
  listIssuerKeys, listOperatorCredentials, feedConsumerHealth; 02 §4.2 row AD-9 ("Noticed by" column).
- **Implements:** daily digest (24 h counts, every grant with operator/reason/length/allowance, open findings, parked work and alerts, last run of each job including the
  backend's last pull, R2 lock + export lag, keys expiring in 30 days, per-channel version counts for the channels the ABO observes); AL-14 (issuer keys via
  `listIssuerKeys` validity, ABO service keys); AL-15 (`feedConsumerHealth` > 5 min); AL-22 (hourly: issuer keys vs `ISSUER_KEYS`, credentials vs the AL-13-announced list);
  housekeeping (done work rows and sent alerts 90 days; invalid-HMAC samples 30 days); daily heartbeat ping; ABO rebuild procedure (replay `ledger/` into an empty D1,
  recompute status, re-inquire the gap, compare with `listGrants`) as a script + runbook.
- **E2E (H-XW):**
  - E2E-P4.11-01 Digest after a scripted day lists the counts, every grant, open findings, job last-runs, export lag and version counts [NFR-04, SR-23].
  - E2E-P4.11-02 A25/FM-17: issuer key `not_after` within 29 days → AL-14 daily.
  - E2E-P4.11-03 FM-10: `feed_consumer` stale for 6 min → AL-15 hourly.
  - E2E-P4.11-04 AD-9: an extra issuer `kid` on the platform not in the pins → AL-22; an unannounced operator credential → AL-22.
  - E2E-P4.11-05 Housekeeping deletes 91-day-old done work rows and sent alerts; facts untouched.
  - E2E-P4.11-06 FM-19: wipe the ABO D1 → replay `ledger/` → facts and status restored; gap re-inquired; a payment with no grant gets one → `already_applied`; reconciliation clean [RC-04].
  - E2E-P4.11-07 Digest send failure retried; daily heartbeat ping sent.

---

## Phase P5 — Shared backend (05 §6.3 step 5)

**Goal.** Give the shared backend issuer-key custody and token issuance, the coverage feed puller and status projection,
and the RPCs of 04 §3.1. The backend only pulls from the platform; it never pushes to vendor services (02 §4.3).

### P5.1 — Issuer key custody, token issuance and the versioned RPC envelope
- **Spec** 087 · **Codebase** backend (+ `e2e/fullstack/` harness) · **Size** L · **Depends** P1.2, P3.2, P4.1 · **Parallel** P4.2–P4.11, P3.x
- **Read:** 01 §7 row R-3 (spike); 02 §3.1 (rows K-1, K-2, "Removed" paragraph); 02 §3.2; 04 §2.1; 04 §3.1 (intro; rows `issue_ai_token`, `issue_billing_token`; "Removed" paragraph, the
  enroll part); 03 §4 rows `issuer_key`, `ai_token_issuance`, `app_settings`, `installation_keys`; 04 §7.1 row RPCs + 04 §7.2 (constants bullet); 02 §6 row K-2.
- **Code:** `20260905120300_fix_aat_lifetime_fallback.sql` (:67-74 installation lookup, :115-124 scopes, :159 signing), `20260801120000_ai_keystore_schema.sql`,
  `20260803140000_b1_review_resolution.sql:284-302`, `backend/tests/ai_token_issuer.sql`, `ai_keystore_rls.sql`, catalog stage-02/06 files.
- **Implements:** R-3 spike → Vault + SQL signing, or the Edge Function signer fallback (OQ-4); `ai_internal.issuer_key` (≥ 2 `kid`s, status, validity, `secret_ref`);
  `issue_ai_token(p_contract_version)` (EdDSA, `kid`, 04 §2.1 claims, `org = current_org_id()`, role from membership, scopes as today, ≤ 600 s);
  `issue_billing_token(p_contract_version)` (administrator only, 300 s, `{token, abo_base_url, expires_at}`, 20 per user per 10 min); internal feed-token minting
  (used by P5.2); `ai_token_issuance` with `aud` + org and per-audience limits; `app_settings` keys incl. `ai.contract_versions` + a contract test against the package
  vectors; `rpc_result.contract_version`; `CONTRACT_VERSION_UNSUPPORTED`; drop `installation_keys`, the single-installation trigger and the enroll/rotate/revoke RPCs
  + `auth_internal` bodies; signing-`kid` switch procedure. **Builds H-FS** (local Supabase + `wrangler dev` platform and ABO + Paymob stub + Node runner + CI job).
- **Out of scope:** feed puller, projection, status RPCs, availability flag (→ P5.2).
- **E2E (H-BK + H-FS):**
  - E2E-P5.1-01 Org A member: `issue_ai_token(1)` → accepted by the local platform `/v1/capabilities`; A's binding created.
  - E2E-P5.1-02 Administrator: `issue_billing_token(1)` → accepted by the local ABO `/v1/offers`; doctor → `FORBIDDEN_ROLE` [FR-10, AD-2].
  - E2E-P5.1-03 Billing token at the platform → 401; AI token at the ABO → 401 [02 §3.2 audience separation].
  - E2E-P5.1-04 Version 2 → `CONTRACT_VERSION_UNSUPPORTED` (raised by `issue_ai_token`); every RPC result carries `contract_version`.
  - E2E-P5.1-05 21st billing token in 10 min → `RATE_LIMITED`.
  - E2E-P5.1-06 A13/A25: new signing `kid` registered on the platform and pinned in the ABO → new tokens accepted everywhere; old tokens valid until expiry; binding unchanged.
  - E2E-P5.1-07 No clinic role can read private key material; no plaintext key column remains [T-4].
  - E2E-P5.1-08 Membership switched to org B → token `org` = B [SR-03].
  - E2E-P5.1-09 `ai.contract_versions` equals the package constants (contract test).

### P5.2 — Coverage feed puller, status projection and status RPCs
- **Spec** 088 · **Codebase** backend · **Size** L · **Depends** P5.1, P3.9 · **Parallel** P4.x
- **Read:** 04 §4.1; 03 §4 (rows `clinic_ai_coverage`, `feed_state` + ordering rule); 04 §3.1 (rows `get_ai_status`, `get_ai_billing_status`, `request_ai_status_refresh`; "Removed",
  the availability part); 04 §3.2; 04 §3.3; 05 §5.4; 01 §7 row R-4 (spike); 05 §4 rows FM-10, FM-11.
- **Implements:** enable `pg_cron` + `pg_net`; the two-phase 30 s pull (fresh feed token, checks for status, version, `after` = cursor and ascending order; abandon responses
  older than 5 min); projection upsert by the ordering rule; `feed_state` failure counting; `request_ai_status_refresh` (administrator, ≤ 1 per 10 s per tenant, immediate pull);
  `get_ai_status` read-time computation + the closed notice vocabulary; `get_ai_billing_status` (administrator; subscription ref computed in SQL to the package vector;
  `abo_base_url`); drop `get_ai_availability`/`set_ai_availability` and `ai.availability`; projection rebuild by cursor reset. R-4 spike locally (confirmed in P8.1).
- **Outputs / freezes:** status RPC results and notice codes (consumed by P6.x). CP-D.
- **E2E (H-FS, compressed scale, rule V4):**
  - E2E-P5.2-01 Grant applied on the platform → within about 60 s `get_ai_status` is available/active [FR-62, FR-63, A2].
  - E2E-P5.2-02 `request_ai_status_refresh` → immediate pull; a second call within 10 s → throttled.
  - E2E-P5.2-03 A10/A28: platform and ABO stopped; stored dates pass → status goes to grace, then lapsed, on time; `stale` + `status_stale` after 2 min [SR-13].
  - E2E-P5.2-04 `ends_soon` at 7, 3 and 1 days only when `queued_count = 0`; staff `get_ai_status` has no prices; staff `get_ai_billing_status` → forbidden [FR-61].
  - E2E-P5.2-05 A14: events from epoch 2, `clinic_seq` 1 replace epoch 1, seq 9; older events ignored.
  - E2E-P5.2-06 The platform answers an unsupported feed version → cursor kept, failure counted, stale [FM-25].
  - E2E-P5.2-07 FM-10: job disabled 5 min → stale; platform `feedConsumerHealth` shows the lag.
  - E2E-P5.2-08 Cursor reset to 0 → identical projection [RC-04].
  - E2E-P5.2-09 SQL subscription ref equals the package vector and the ABO/platform values [FR-66].
  - E2E-P5.2-10 FM-11: Supabase stopped during a payment → the ABO and platform still provision; status catches up after restart.
  - E2E-P5.2-11 Band 90 event → `allowance_low` for every role [A29].

---

## Phase P6 — Desktop (05 §6.3 step 6)

### P6.1 — Desktop contract versions, token minting and AI status reads
- **Spec** 089 · **Codebase** frontend · **Size** M · **Depends** P5.2 · **Parallel** P4.9–P4.11
- **Read:** 04 §3.1 (intro; rows `issue_ai_token`, `get_ai_status`); 04 §3.2; 04 §3.4 (first bullet "When to read status"); 04 §3.5 row "Frontend status";
  04 §7.1 rows Desktop→RPCs and Desktop→platform; 04 §7.2 (constants bullet); 04 §6.6 row frontend.
- **Code:** `lib/core/ai/discovery_client.dart`, `supabase_aat_mint_port.dart:22-30`, `lib/features/ai/availability/ai_availability_reader.dart:17-18`,
  `ai_availability.dart:11-15`, `lib/app/app.dart:47-57`, `frontend/test/widget/ai/`.
- **Implements:** `lib/core/contract_versions.dart` + a contract test against the package vectors; `Aip-Contract-Version` on every platform call; `p_contract_version` on
  every RPC; the new `issue_ai_token` signature; `get_ai_status` replaces the availability reader; refresh on open, resume, coverage denial, `next_change_at` and
  every 5 min, contacting the backend only; notice rendering (staff form vs administrator form with a renew action wired in P6.3); the inline "update the app" state;
  **H-FL** (Dart `fullstack`-tagged tests on H-FS + widget scenarios; CI job).
- **E2E (H-FL):**
  - E2E-P6.1-01 Staff session: status via `get_ai_status` shows active for a granted org; a network spy sees no call to the ABO host [FR-61].
  - E2E-P6.1-02 App resume and the `next_change_at` timer both trigger a refresh.
  - E2E-P6.1-03 A28: staff see `ends_soon` "ask your administrator" at 7, 3 and 1 days, with no prices and no purchase action; administrators see the renew action [FR-26, FR-27].
  - E2E-P6.1-04 A29: `allowance_low` for staff and administrators.
  - E2E-P6.1-05 RPC answers `CONTRACT_VERSION_UNSUPPORTED` → inline "Update the app to use AI", no dialog [NFR-09, FR-64].
  - E2E-P6.1-06 Platform calls carry the header; a platform 400 unsupported → the same update state.
  - E2E-P6.1-07 The contract test fails when the Dart constants differ from the vector file.

### P6.2 — Desktop denial states and the administrator coverage view
- **Spec** 090 · **Codebase** frontend · **Size** M · **Depends** P6.1 · **Parallel** P6.3
- **Read:** 04 §3.4 (denial table); 04 §4.2 (denial-code table; rows `/v1/coverage`, `/v1/usage`); 04 §3.5 rows "Frontend status" and "Frontend usage"; 02 §2 row TB-3.
- **Code:** `lib/features/ai/degraded/ai_degraded_view.dart:33-110`, `ai_degraded_mode.dart:18-51`, `lib/core/ai/taxonomy.dart:23-42`,
  `lib/core/ai/usage_summary_client.dart:40-53`, `lib/features/ai/host/ai_feature_host_page.dart:148-152, 280-305`.
- **Implements:** taxonomy for the 04 §4.2 codes mapped to the FR-65 classes in `AiDegradedView` (inline only; staff vs administrator wording; `retry_after`);
  a denial triggers a status refresh; `usage_summary_client` becomes a `/v1/coverage` client; the gauge is administrator-only; staff never call `/v1/coverage`
  or `/v1/usage`.
- **E2E (H-FL):**
  - E2E-P6.2-01 Lapsed clinic: AI request denied `coverage_lapsed` → staff inline "contact your administrator"; the administrator sees renew/buy [FR-65].
  - E2E-P6.2-02 `allowance_exhausted` → state shown and status refreshed.
  - E2E-P6.2-03 `suspended` → the administrator sees "Contact support" + subscription reference.
  - E2E-P6.2-04 `concurrency_limited`/`rate_limited` → "AI busy" with `retry_after`.
  - E2E-P6.2-05 `coverage_unknown` or network failure → "AI service unreachable" [G5].
  - E2E-P6.2-06 The administrator gauge shows live allowance from `/v1/coverage`; a staff session makes no `/v1/coverage` or `/v1/usage` call [A28].
  - E2E-P6.2-07 `forbidden_capability` shows the plan name to administrators.

### P6.3 — Administrator billing: offers, contact and checkout flow
- **Spec** 091 · **Codebase** frontend · **Size** L · **Depends** P6.1, P4.5 · **Parallel** P6.2
- **Read:** 04 §2.2 (rows offers, billing contact, the three checkout rows, Rules); 04 §2.3; 04 §3.1 rows `issue_billing_token`, `request_ai_status_refresh`;
  03 §5.1 (shown-state table); 04 §3.5 row "Frontend billing"; 05 §8 rows A1, A2, A12, A30.
- **Implements:** billing-token client (minted per use, renewed before 300 s); ABO client with `Abo-Contract-Version`; offers screen (localised copy, terms
  acceptance); billing-contact form; checkout → system browser via `url_launcher`; progress polling (Waiting/Failed/Paid/Active/Abandoned); `starts after_current`
  shown before paying; resume open checkouts from any desktop; on Active, call `request_ai_status_refresh`; error handling (`offer_unavailable`,
  `billing_contact_required`, `terms_not_accepted`, `provider_unavailable`, `rate_limited`); en/ar strings; administrator-only entry point.
- **Outputs:** CP-E.
- **E2E (H-FL on H-FS, payment via the H-PAY fixture):**
  - E2E-P6.3-01 CP-E / A1: offers → contact → checkout → stub payment → polling shows Active → refresh RPC → `get_ai_status` active → an AI request succeeds.
  - E2E-P6.3-02 A2/A12: a second desktop session (other branch) sees the open checkout via `?open=1` and Active status; closing the app mid-payment still provisions.
  - E2E-P6.3-03 A30: an active clinic buying again sees "starts after the current term" before paying.
  - E2E-P6.3-04 A8: the price changes mid-flow → `offer_unavailable` → the new price is shown before paying.
  - E2E-P6.3-05 A5: decline, then a retry on the same page → Failed, then Active.
  - E2E-P6.3-06 Staff user: no billing entry point; `issue_billing_token` never called [AD-2].
  - E2E-P6.3-07 ABO answers unsupported version → billing screens show the update state.

### P6.4 — Administrator subscription, payment history and commercial notices
- **Spec** 092 · **Codebase** frontend · **Size** M · **Depends** P6.3 · **Parallel** P7.1
- **Read:** 04 §2.2 rows `/v1/subscription`, `/v1/payments`; 04 §3.1 row `get_ai_billing_status`; 04 §3.2 (notice table); 05 §8 rows A6, A15, A16.
- **Implements:** subscription page (`get_ai_billing_status` + `/v1/subscription`: plan, dates, allowance, queued/held counts, subscription ref, commercial
  notices); payment history with cursor paging, classification and reversals; "contact support" with the subscription reference.
- **E2E (H-FL on H-FS):**
  - E2E-P6.4-01 A6: duplicate payment → `duplicate_payment` notice; history shows both, the second `likely_duplicate`; queued count 1.
  - E2E-P6.4-02 A16: refund → `reversal_recorded` + `terms_held`; history shows the reversal; status `ended_reversed`.
  - E2E-P6.4-03 Late payment → `late_payment_honoured`; withheld mismatch → `payment_withheld`.
  - E2E-P6.4-04 Paging over 30 payments.
  - E2E-P6.4-05 A36 desktop path: org A's administrator never sees B's subscription or payments.

## Phase P7 — Clean-up and cross-system verification (05 §6.3 step 7)

### P7.1 — Clean-up of dependent paths and the `/control` residue guard
- **Spec** 093 · **Codebase** ai-platform-viewer, `ai-platform/scripts`, docs, CI · **Size** S · **Depends** P3.10, P4.9 · **Parallel** P6.x
- **Read:** 04 §6.6; 05 §6.2 (second bullet).
- **Implements:** remove the viewer's control pages and its catalog operations that use `/control/*`; viewer clinic pages use issuer tokens (test issuer key) and send
  `Aip-Contract-Version`; delete `bootstrap-routing-policy.sh`; mark superseded parts of `docs/architecture/ai-platform/` and `docs/testing/catalog/` with links to the
  v2 design (rule V2); CI residue guard failing on `/control/`, `OPERATOR_BEARER_TOKEN`, `set_ai_availability`, `enroll_installation_keypair`, `installation_key` outside migrations.
- **E2E:**
  - E2E-P7.1-01 Viewer against the local platform: capabilities and request pages work with issuer tokens.
  - E2E-P7.1-02 The residue guard passes; a negative fixture containing `/control/` fails it [FR-91].
  - E2E-P7.1-03 The viewer build contains no control routes; viewer smoke tests pass without a bearer token.

### P7.2 — Cross-system security and isolation suite
- **Spec** 094 · **Codebase** `e2e/fullstack/` (tests; defect fixes only, with no contract change) · **Size** M · **Depends** P6.4, P4.11 · **Parallel** P7.3
- **Read:** 02 §2; 02 §4.2; 02 §4.3; 05 §8 rows A22, A26, A27, A35, A36.
- **E2E (H-FS):**
  - E2E-P7.2-01 AD-1: junk to `/notify` is rate-limited and not stored; `/return` cannot create service [SR-01].
  - E2E-P7.2-02 AD-2: staff cannot mint a billing token; `/v1/coverage` → 403; no RPC writes status [SR-07].
  - E2E-P7.2-03 AD-3/A36: org A's administrator replays B's ids on every ABO route, every RPC and the platform routes → not found; B unchanged.
  - E2E-P7.2-04 AD-5: forged callback with a leaked HMAC secret → the inquiry does not confirm → no payment.
  - E2E-P7.2-05 AD-8: simulated compromised ABO → a paid grant beyond the plan bound is rejected; one within the bound applies but raises AL-11, AL-17 and `grant_without_payment`;
    HP without an assertion is rejected; a substituted operation shows its real content in the AL-11 body.
  - E2E-P7.2-06 AD-11: Access JWT alone → H actions work, HP rejected. AD-12: passkey + session → ceilings still enforced [A27].
  - E2E-P7.2-07 A35: neither Worker's config holds a Supabase credential; billing, AI and feed tokens are rejected by PostgREST.
  - E2E-P7.2-08 K-1: the Supabase session JWT never leaves for the ABO or platform (Dart network capture).
  - E2E-P7.2-09 A26 code half: a stored CI/staging token cannot reach any HP method (no passkey); the rest is P8.3 policy.

### P7.3 — Contract version matrix
- **Spec** 095 · **Codebase** `e2e/fullstack/` + per-codebase test variants · **Size** M · **Depends** P6.4, P4.11 · **Parallel** P7.2
- **Read:** 04 §7; 05 §6.1 ("Version matrix" bullet); 05 §4 row FM-25.
- **Implements:** a matrix harness that builds receivers and senders with overridden package constants (N+1) and runs every 04 §7.1 channel with N, N−1 and unsupported.
- **E2E:**
  - E2E-P7.3-01 Per channel (all ten rows of 04 §7.1): N accepted and answered in N; unsupported → that channel's refusal, checked before auth and before any write.
  - E2E-P7.3-02 FM-25: ABO on N+1 against a platform on N → `rejected` → row parked + AL-07; deploy the platform accepting N and N+1 → retry applies.
  - E2E-P7.3-03 Feed puller on N against a platform accepting only N+1 → cursor kept, stale.
  - E2E-P7.3-04 A retried work row resends its stored envelope in its original version.
  - E2E-P7.3-05 Worker on N with a DO on N+1 → `coverage_unknown`.
  - E2E-P7.3-06 Desktop below the minimum version → update state on all three desktop channels (04 §7.3).
  - E2E-P7.3-07 Unknown `v` on the return URL → inquiry still scheduled. **CP-F follows this unit.**

## Phase P8 — Staging acceptance (05 §6.3 step 8)

### P8.1 — Staging environment, external monitors and the staging profile
- **Spec** 096 · **Codebase** wrangler envs (ai-platform, abo), backend config, `e2e/fullstack/staging/`, ops scripts · **Size** M · **Depends** P7.1 · **Parallel** P7.2, P7.3
- **Read:** 05 §6.1; 02 §1.4 (last paragraph); 02 §4.4; 02 §5; 05 §1 (External row); 05 §2 row AL-21; 01 §7 row R-6; 05 §7.
- **Implements:** staging wrangler envs in a separate Cloudflare account (staging `DURATION_SCALE`, Access application, Email Routing destination, R2 bucket lock);
  a staging Supabase project + migration deploy; Paymob test-integration secrets and callback URL; external heartbeat monitor (ABO minute, platform 5-min, digest
  daily) and hourly audit-log watcher with a read-only token, configured as code; the three test offers (20/60/240 credits) published through the console; R-4 confirmed
  on hosted Supabase; NFR-08 cost check recorded.
- **E2E (H-STG):**
  - E2E-P8.1-01 ABO cron disabled → the heartbeat monitor raises AL-21 over its own channel [NFR-04].
  - E2E-P8.1-02 A staging deploy and a secret change → the watcher alerts within the hour [A26 detection].
  - E2E-P8.1-03 Smoke: monthly test purchase with a Paymob test card → AI active in about 1 min; term ends after 30 min; grace about 7 min.
  - E2E-P8.1-04 `workers.dev` and preview URLs unreachable; the ops host requires Access.

### P8.2 — Staging acceptance A1–A36
- **Spec** 097 · **Codebase** `e2e/fullstack/staging/` · **Size** L · **Depends** P8.1, P7.2, P7.3
- **Read:** 05 §8; 05 §6.1; 00 §11.
- **Implements:** STG-A01…STG-A36 as runner scripts, with scripted manual steps (dashboard refund, test cards, blocked notify URL, disabled platform route); an evidence report per scenario
  citing the earlier E2E IDs (section 5, D2); FM drills STG-FM-12 (catch-up after an outage window), STG-FM-13/14 (bad deploy, rollback, retry parked).
- **E2E:** STG-A01 … STG-A36 (one each, all three term lengths for A1), STG-FM-12, STG-FM-13, STG-FM-14. **CP-G = launch gate (FR-90).**

### P8.3 — Launch readiness checks
- **Spec** 098 · **Codebase** ops scripts + runbooks · **Size** S · **Depends** P8.2
- **Read:** 05 §6.2; 05 §10; 02 §6.
- **Implements:** a read-only `launch-check` against a target environment (no `/control` routes; `workers_dev`/previews off; every channel on version 1 and the backend copy matching;
  AL-23 clear; ≥ 2 active operator credentials; issuer and service keys registered and pinned; no terms or grants in platform D1; heartbeat and watcher live); runbooks for
  pre-launch installation deletion, the FR-92 pilot grant, bootstrap ceremony, rotations (02 §6), compromise response, rebuilds (05 §5); a checklist of the operational items in section 5, D3 with owners.
- **E2E:**
  - E2E-P8.3-01 `launch-check` against staging configured production-like → all green.
  - E2E-P8.3-02 Staging with `workers_dev` re-enabled, or a single operator credential → the check fails and names the condition.

---

## 5. Coverage and traceability


### D1. Design section → owning unit(s)

The first unit listed is the primary owner; the others own named slices of the section, as stated in their unit rows.

| v2 section | Owner(s) |
| ---------- | -------- |
| 02 §1.1 Components (+ JSON logs, failing crons alert) | P3.1 (platform), P4.1 (ABO), P8.1 (external monitor and watcher) |
| 02 §1.2 ABO modules; import boundary G6 | P4.1 (layout), P4.2 (port, boundary check); modules P4.1–P4.11 |
| 02 §1.3 Platform surfaces | P3.1 (entrypoint), P3.2 (`/v1/requests`, `/v1/capabilities` identity), P3.9 (`/v1/coverage`, feed, `/v1/usage` removed), P3.10 (`/control/*` removed) |
| 02 §1.4 Hostnames, `workers_dev`/previews | P4.1 (billing host), P4.6 (ops host), P3.10 + P4.1 (flags), P8.1 (staging account) |
| 02 §1.5 Key flows | P4.4 (purchase → AI on), P5.2 (status), P6.3 (desktop part) |
| 02 §2 TB-1…TB-10 | TB-1 P4.3; TB-2 P4.1/P4.2; TB-3 P3.2/P3.9; TB-4 P1.1/P1.2; TB-5 P5.2; TB-6 P3.1/P3.3; TB-7 P4.6/P4.7; TB-8 P4.3; TB-9 P3.1/P4.1; TB-10 P8.1/P8.3; verified together in P7.2 |
| 02 §3.1 Credentials K-1…K-10 + removed | K-1 P7.2; K-2 P5.1/P3.2; K-3 P3.3; K-4 P4.4; K-5/K-6 P4.2/P4.3; K-7 P3.1/P4.7/P4.9; K-8 P4.6; K-9/K-10 P8.1; removals P3.2, P3.10, P5.1 |
| 02 §3.2 Token profiles | P5.1 (mint), P3.2 (AI verify), P4.1 (billing verify), P3.9 (feed verify) |
| 02 §3.3 Authorization classes | P3.1 (framework); ABO-side HP P4.7 |
| 02 §4.1–§4.3 Threat model, defence in depth | Controls in the units named per TB/AD; adversary scenarios P7.2 |
| 02 §4.4 Residual risks / operating policy | P8.1 (watcher), P8.3 (policy checklist) — operational |
| 02 §5 Out-of-band alerting | P3.1, P4.1, P8.1 |
| 02 §6 Rotation and revocation | K-2 P3.2/P5.1/P4.9; K-3 P4.4; K-4 P3.3/P4.4/P4.9; K-5 P4.5; K-7 P3.1; runbooks P8.3 |
| 02 §7 Constitution check | Every unit's `plan.md` (rule S12) |
| 03 §1 Stores and authority | Structural; each store's owner below |
| 03 §2.1 Conventions | P4.1 |
| 03 §2.2 Offers and terms | P4.1 (tables, read), P4.7 (HP publish/retire) |
| 03 §2.3 Billing contact | P4.1, P4.7 (erasure) |
| 03 §2.4 Checkout | P4.2 |
| 03 §2.5 Evidence | P4.3 |
| 03 §2.6 Payment | P4.3; `payment_release` P4.7 |
| 03 §2.7 Reversal | P4.5; manual P4.7 |
| 03 §2.8 Grant requests | P4.4 (paid), P4.8 (complimentary, transfer) |
| 03 §2.9 Work rows | P4.3 (framework), P4.4/P4.5/P4.8 (kinds) |
| 03 §2.10 Alerts, findings, audit, payouts, `coverage_view` | `alert` P4.1; `operator_action` P4.6; `finding`/payouts P4.10; `coverage_view`/`feed_cursor` P4.2 |
| 03 §2.11 Paymob tables | P4.2 (intention), P4.3 (txn, state_seen) |
| 03 §3.1 DO storage | P3.3 (tables), P3.4 (`hot` admission), P3.6 (suspended), P3.8 (transfer flags) |
| 03 §3.2 Platform D1 tables | `issuer_key`/`tenant_binding` P3.2; `operator_credential`/`assertion_used`/`platform_alert`/`control_audit` P3.1; `service_key`/`plan_version`/mirror/event/ledger P3.3; `usage_*` P3.4; `ceiling_policy` P3.6; `grant_void` P3.7; `transfer*` P3.8; `fallback_admission`/`feed_consumer` P3.9; drops P3.2 (key), P3.9 (grace queue), P3.10 (rest) |
| 03 §3.3 R2 grant ledger | P3.3, P3.7 |
| 03 §4 Backend records + ordering rule | Tenancy P1.1/P1.2; `issuer_key`, `ai_token_issuance`, `app_settings`, drops P5.1; projection, `feed_state` P5.2; ordering rule P5.2 + P4.2 |
| 03 §5.1 Checkout lifecycle | P4.2 (open/open_failed), P4.3 (attempts, paid), P4.4 (Active), P4.5 (expired, paid_late), P4.6 (cancelled) |
| 03 §5.2 Payment lifecycle | P4.3, P4.4, P4.5, P4.7 (release) |
| 03 §5.3 Grant | P3.3 (paid), P3.6 (complimentary, adjustment), P3.8 (transfer) |
| 03 §5.4 Term | P3.3 (placement), P3.4 (exhausted), P3.5 (expiry/grace/renewal), P3.7 (held/reversed/voided), P3.8 (transferred, deletion) |
| 03 §5.5 Reversal | P4.5 (ABO), P3.7 (platform) |
| 03 §5.6 Work row | P4.3 |
| 03 §5.7 Clinic coverage state | P3.3, P3.4, P3.5, P3.6, P3.7, P3.8 (by state) |
| 03 §6.1 Placement and dates | P3.3 (placement, calendar, scale), P3.5 (boundaries) |
| 03 §6.2 / §6.3 Admission, exhaustion | P3.4 |
| 03 §6.4 Grace | P3.5 |
| 03 §6.5 Fallback | P3.9 |
| 03 §6.6 Overshoot | P3.4 (normal), P3.9 (outage), P3.11 (load) |
| 03 §6.7 Events, alarm, write budget | P3.3 (outbox), P3.5 (boundary alarm), P3.11 (budget) |
| 03 §6.8 Worked examples | P3.4, P3.5 scenarios |
| 03 §7 Identifiers | P2.1 (+ vectors); SQL copy P5.2 |
| 03 §8 Retention | P3.8 (platform), P4.1 (ABO facts), P4.3 (HMAC samples), P4.11 (housekeeping), P5.2 (projection) |
| 04 §1.1–§1.2 Transport, envelope | P2.1/P2.2, P3.1 |
| 04 §1.3 Methods | Operator credentials P3.1; issuer keys P3.2; grant (paid), coverage reads, service keys, plan versions P3.3; complimentary, adjustment, ceiling, suspend/resume, inspect P3.6; voids, release, listGrantsForVoid P3.7; transfer, delete P3.8; `feedConsumerHealth` P3.9; kill switch…token contract, `supportLookup` P3.10 |
| 04 §1.4 Envelope and validation | P3.3 (steps 1–3, 5 binding; velocity), P3.6 (step 4), P3.7 (`voided`), P3.8 (`transferred_out`, awaiting) |
| 04 §1.5 Operator assertion | P2.2 (verify), P3.1 (registry rules), P4.7 (ceremony) |
| 04 §1.6 / §1.7 Receipt, snapshot | P2.2 (types), P3.3 (produce) |
| 04 §2.1 Token claims | P2.2, P5.1, P3.2 |
| 04 §2.2 / §2.3 Clinic API, errors | P4.1 (offers, contact, rules, errors), P4.2 (checkouts), P4.4 (subscription, payments) |
| 04 §3.1 RPCs | P5.1 (issue_*), P5.2 (status RPCs, availability removal) |
| 04 §3.2 / §3.3 Status, notices, read-time | P5.2 |
| 04 §3.4 Desktop behaviour | P6.1 (reads), P6.2 (denials) |
| 04 §3.5 Affected files | P5.1, P5.2, P6.1–P6.4 |
| 04 §4.1 Feed | P3.9 (platform), P5.2 (puller) |
| 04 §4.2 Clinic routes, codes | P2.1 (header), P3.4 (codes, capabilities), P3.9 (`/v1/coverage`, `/v1/usage`) |
| 04 §5.1–§5.3 Provider port, Paymob | P4.2 (create, capabilities, cancel), P4.3 (parse, inquire, normalise), P4.5 (reversal normalisation), P4.10 (payoutLines); refund/mandate stubs P4.2 |
| 04 §6.1–§6.5 Platform change list | Spread across P3.1–P3.11 as listed in each unit's Read row |
| 04 §6.6 Other affected paths | P7.1 (viewer, script, docs), P6.x (frontend) |
| 04 §7 Contract versioning | P2.1 (constants), every channel unit, P5.1/P6.1 (copies), P7.3 (matrix) |
| 05 §1 Scheduled work | ABO P4.1, P4.2, P4.3, P4.4, P4.5, P4.11; platform P3.1, P3.3, P3.4, P3.9; backend P5.2; external P8.1 |
| 05 §2 Alerts | AL-01/02/05/09 P4.3; AL-03/06/08 P4.5; AL-04/07/23 P4.4; AL-10 P4.10; AL-11/17 P3.3; AL-12 P3.6; AL-13 P3.1 (+P3.2, P3.3); AL-14/15/22 P4.11; AL-16 P4.1; AL-18 P3.8; AL-19 P3.6 + P3.10; AL-20 P3.2; AL-21 P8.1 |
| 05 §3.1 Views | P4.6 |
| 05 §3.2 Actions | P4.6 (H, ABO), P4.7 (HP, ABO), P4.8 (coverage relays), P4.9 (configuration relays) |
| 05 §3.3 Reconciliation | P4.10 |
| 05 §3.4 Digest | P4.11 |
| 05 §4 Failure modes | FM-01/02/03/18 P4.5; FM-04/05/24 P4.4; FM-06 P3.9; FM-07/08/15/21 P4.3; FM-09/22 P4.2; FM-10/11 P5.2; FM-12/13/14 P8.2 (plus P3.5-06, P4.4-04 locally); FM-16 P3.1/P4.1; FM-17 P4.11; FM-19 P4.11; FM-20 P3.11; FM-23 P3.8; FM-25 P7.3 |
| 05 §5 Rebuilds | §5.1 P4.11; §5.2/§5.3 P3.11; §5.4 P5.2 |
| 05 §6.1 Staging profile, local stubs, matrix | P8.1 (profile), P4.2/P4.3 (stub, fixture), P7.3 (matrix) |
| 05 §6.2 Launch conditions | P8.3 (checks + checklist) |
| 05 §6.3 Delivery sequence | Phases P1–P8 (rule S1) |
| 05 §7 Operating cost | P3.11 (write budget), P8.1 (NFR-08 check) |
| 05 §8 Acceptance | P8.2 (D2) |
| 05 §9 / §10 Traceability, gaps | P8.2 report; gaps tracked in D3 |

FM-07 (ABO D1 unavailable) is covered by P4.3 fault injection (callback gets 5xx; the sweep recovers in P4.5); its scenario is added under E2E-P4.3-09's pattern.

### D2. A1–A36 → unit where first E2E-verified locally (then STG-A## in P8.2)

| A | Unit(s) | A | Unit(s) | A | Unit(s) |
| - | ------- | - | ------- | - | ------- |
| A1 | P4.4-01 (full stack P6.3-01) | A13 | P3.2-04, P5.1-06 | A25 | P4.11-02, P5.1-06 |
| A2 | P4.4-08, P5.2-01, P6.3-02 | A14 | P3.8-01, P4.8-04, P5.2-05 | A26 | P7.2-09, P8.1-02 (Partial: policy) |
| A3 | P4.5-01 | A15 | P3.7-01, P4.7-05 | A27 | P3.6-02, P4.8-02, P7.2-06 |
| A4 | P4.4-02 | A16 | P4.5-04/05, P6.4-02 | A28 | P5.2-03/04, P6.1-03, P6.2-06 |
| A5 | P4.3-04, P6.3-05 | A17 | P3.7-03, P4.5-06 | A29 | P3.4-08, P5.2-11, P6.1-04 |
| A6 | P4.3-07, P4.4-05, P6.4-01 | A18 | P4.10-05 | A30 | P4.2-02, P6.3-03 |
| A7 | P4.3-05 | A19 | P3.6-07, P4.8-03 | A31 | P3.4-05 |
| A8 | P4.2-04, P4.7-01, P6.3-04 | A20 | P3.6-01, P4.8-01 | A32 | P3.4-06 |
| A9 | P3.5-01 | A21 | P4.1-03, P4.2-04, P4.7-02 | A33 | P4.1-03, P4.7-02 |
| A10 | P3.5-02, P5.2-03 | A22 | P4.2-07, P7.2-03 | A34 | P3.4-07, P3.11-05 |
| A11 | P3.5-05 | A23 | P4.3-03, P4.5-02 | A35 | P7.2-07 |
| A12 | P4.2-07, P6.3-02 | A24 | P3.8-04, P4.8-05 | A36 | P1.1-05, P1.2-02, P4.4-09, P7.2-03 (Conditional → met by P1) |

### D3. Deliberately operational / non-code (tracked in the P8.3 checklist, owner = developer)

- RC-06 legal confirmation of the no-refund policy; R-9 advice on payer contact data and erasure timing (01 §7). Launch conditions, 05 §6.2.
- 02 §4.4 operating policy: production deploys and secret changes only from an interactive session with hardware-key MFA; no stored token with production rights.
  P8.3 checks it; the audit watcher (P8.1) detects breaches. A26 stays Partial by design.
- IdP hardware-key MFA and 1-hour Access sessions (TB-7, K-8): Access configuration in P8.1, verified by checklist.
- Production key generation and registration, bootstrap and second credential, pilot grant (FR-92), deletion of pre-launch installations: P8.3 runbooks, run at launch.
- Paymob dashboard settings (callback URLs, integration ids) and HMAC/API key rotation in the dashboard: P8.1/P8.3 runbooks.
- NFR-08 plan-allowance confirmation (05 §7) and D1 Time Travel (a built-in feature): recorded in P8.1.
- FR-80 monthly payout CSV import: a routine operator action (05 §10), supported by P4.10.

---

## 6. Open questions and defaults

Until the owner answers an item, units proceed on the default stated in it.

1. **OQ-2: Multi-organisation users.** P1.1 adds membership and an active-org claim, set from the user's sole membership at sign-in. If any real user will belong to
   more than one clinic at launch, the desktop needs an organisation switcher, which the design does not specify. Is that out of scope?
   **Default:** out of scope; the active organisation is changed only through the `set_active_organization` RPC.
   Sign-in rule for more than one live membership: the access-token hook keeps the stored active-org record when it
   still names a live membership; otherwise it writes the deterministically first live membership — earliest
   membership `created_at`, then lowest `organization_id` — and the claim carries that organisation. With no live
   membership the claim carries no organisation.
2. **OQ-3: Staging accounts earlier than P8.** The R-2 spike (Paymob sandbox, in P4.2/P4.3 research) and the R-4 spike (hosted pg_cron/pg_net, P5.2) need a Paymob
   test integration and a staging Supabase project well before P8.1. Can those accounts be provisioned at the start of P4.2?
   **Default:** yes, provisioned at the start of P4.2; if not available, P4.2 and P5.2 stop at their spike step.
3. **OQ-4: R-3 fallback adds a runtime part.** If Vault + SQL signing fails the P5.1 spike, the design's fallback is a single-purpose Supabase Edge Function signer.
   That is a new deployable on the backend side. Is it acceptable under the constitution, or must the spike pass with SQL?
   **Default:** P5.1 stops and escalates if the spike fails; the fallback is used only with the owner's approval.
4. **OQ-5: Time-control deviations.** Local E2E relies on a test-only clock control (absent from production and staging configs, asserted by a config test) and, in
   H-FS only, on a faster `DURATION_SCALE` (1 month = 60 s, keeping the 30:1 ratio). The design fixes only the staging mapping. Is that interpretation acceptable?
   **Default:** accepted as described in rule V4.
5. **OQ-6: Desktop E2E depth.** Flutter is verified through Dart client tests against the full local stack plus widget scenario tests, without a Windows
   `integration_test` driver. Acceptable, or should P6.3 add one driven desktop golden path?
   **Default:** no `integration_test` driver; Dart client tests against H-FS plus widget scenario tests (harness H-FL).

Smaller risks noted inside units (no decision needed now): the per-channel version counts in the digest (P4.11) are limited to channels the ABO observes. pg_net in the
Supabase container must reach `wrangler dev` on the host (P5.1/P5.2). The `file:` package must bundle under wrangler and work in the Miniflare auxiliary worker (P2.1, P4.2).

