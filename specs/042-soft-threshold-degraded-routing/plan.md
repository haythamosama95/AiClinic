# Implementation Plan: Soft-threshold degraded routing (F4)

**Branch**: `ai/042-f4-soft-threshold-degraded-routing` | **Date**: 2026-08-02 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/042-soft-threshold-degraded-routing/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

F4 wires soft-threshold quota pressure into degraded routing: when period usage crosses the
entitlement soft threshold but budget remains, the Quota DO admits with `{ degraded: true }`, the
gateway sets `routing_tier = degraded`, the D2 router selects the degraded target chain, and the
client receives `accepted { degraded_notice }` rather than a refusal. Hard budget exhaustion returns
`quota_exhausted` with A2's `period_reset` (entitlement period end), disables the additive AI path
with a clear reason, and never hard-locks clinical or non-AI workflows.

F4 sits in Band F after D2 and B4 (`Needs: D2, B4`); it extends B4's admission allow path with the
soft-threshold branch B4 deferred and supplies the `routing_tier` signal D2's router already matches
(delivery plan §3.7).

## Technical Context

**Language/Version**: TypeScript on Cloudflare Workers (existing `ai-platform/` Vitest ~
`@cloudflare/vitest-pool-workers` / Wrangler stack); Durable Object storage for Quota DO counters.

**Primary Dependencies**: Existing Worker tree under `ai-platform/`. Consumes B4 Quota DO + stage-8
admission and D2 router without rewrite of their frozen cores; extends admission response with
`degraded` / `period_end` (B4 contract already names F4 as the extension consumer). Extends C3
`createRequestRow` to populate A5's existing `ai_request.routing_tier` column only. Uses A2
`supplementaryFieldsForCode` / `periodReset` and A6 `accepted` SSE framing for wire outcomes. No new
external packages; no Flutter / `backend/` changes.

**Storage**: Quota DO in-object period counters + entitlement snapshot already supplied on admission
(B4). Platform D1 `ai_request.routing_tier` column already from A5 — F4 writes the value through C3's
journal writer and introduces **no** migration / schema change (FR-006; Key Entities). No R2 write
added by this slice. No Supabase write path.

**Testing**: Vitest (`npx vitest run`) at delivery plan §3.11.6 row F4 — **Integration** — mapped to
§13.5 **Pipeline tests** (fake provider / deterministic policy; Miniflare DO + D1; spy on Quota DO
fetch count). Fixture style per Clarification: seed Quota DO counters / entitlement snapshot into the
target region (below soft, at/above soft with budget left, hard-exhausted) before the request under
test. Named cases T1–T7 under `ai-platform/test/soft-threshold-routing.test.ts`. Suite joins CI
permanently (delivery plan §3.10).

**Target Platform**: Cloudflare Worker + per-installation Quota Durable Object under `ai-platform/`.
No `frontend/` or `backend/` code.

**Project Type**: Additive AI gateway slice — soft-threshold admission branch, gateway `routing_tier`
/ `degraded_notice` wiring, and integration with the D2 router. Per §14: non-primary, no domain
logic, no business data, no write path into Supabase.

**Performance Goals**: Soft-threshold evaluation rides the existing single stage-8 Quota DO round
trip — no second DO trip for the degraded decision (FR-009; §7.5; §13.6; delivery plan §6.4). No
second R2 object per request. Guard I/O budget inherited from B4/C3 unchanged.

**Constraints**: Never hard-lock the product on quota exhaustion (constitution V; FR-001). Client
cannot inject `routing_tier` or soft-threshold trigger (FR-008). Do not rewrite B4's four admission
questions, credit, ephemeral store, or fail-open grace. Do not redefine D2 policy shape or provider
port. Do not persist `routing_decision` in this slice. Do not invent `reset_at` — populate A2
`period_reset` from entitlement `period_end`. Rate-limit (`rate_limited`) remains B3. E4 owns client
degraded-mode UX chrome; F4 supplies gateway outcomes only.

**Scale/Scope**: Two §4 components named by delivery plan Canonical (§4.3.3 and §4.3.7) plus thin
extensions to C3 journal writer and A6 accepted-event data for Freezes wiring. Ten FRs; seven named
integration tests; two frozen contract artifacts; roughly 16–20 tasks — under the ~25-task ceiling
(delivery plan §6.3 / skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — soft-threshold
      downgrade and hard-exhaustion disable-without-lock keep AI additive under quota pressure for
      small-to-mid multi-branch clinics (spec Clinic Fit; constitution I; §4.3.3; §8.8).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — extends the existing Quota DO admission answer
      and in-isolate router signal inside one Worker; no new deployable, queue, or store.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — F4 lives only
      in `ai-platform/`; no Flutter prompt/provider/model identifiers; no Supabase domain writes
      (§14 acknowledgement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — F4 writes only platform D1
      `ai_request.routing_tier` (existing A5 column) via C3's journal writer; no clinic-DB write path.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — soft threshold and budget come from the
      installation-scoped entitlement snapshot; `routing_tier` is gateway-set and journaled; clients
      cannot inject tier (FR-008).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — soft threshold degrades
      routing and notifies; hard exhaustion disables the additive AI affordance with clear reason /
      admin-addressable `period_reset` and leaves all non-AI workflows usable (constitution V;
      FR-001; FR-004; §8.8).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no
domain logic, no business data, and no write path into Supabase. F4 extends Quota DO admission and
gateway routing signals only; it never writes clinic data and never hard-locks non-AI workflows.

## Project Structure

### Documentation (this feature)

```text
specs/042-soft-threshold-degraded-routing/
├── plan.md                                         # This file
├── spec.md                                         # Authoritative feature spec (input)
├── contracts/
│   ├── soft-threshold-admission.md                 # Freezes: soft/hard admission answer extension
│   └── degraded-routing-signal.md                  # Freezes: routing_tier, degraded path, degraded_notice
└── quickstart.md                                   # Written during the implement-phase Documentation task
```

`data-model.md` is **not** produced — F4 defines no entities and introduces no schema change; A5
already owns `entitlement.soft_threshold` and nullable `ai_request.routing_tier` /
`routing_decision` (spec Key Entities; escalation resolution).

`research.md` is **not** produced — the research is `docs/architecture/17-ai-platform.md`.

`contracts/` is produced because **Freezes** entries have wire shapes later slices' **Consumes**
must bind to: soft-threshold `{ degraded }` admission branch; hard-exhaustion `period_end` → A2
`period_reset`; gateway `routing_tier`; `accepted { degraded_notice }`.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:

- **§1 Architecture context** — F4 row of the delivery plan (§3.7) and Implements (§4.3.3, §8.8,
  §4.3.7); what the spec delivered; what the plan scoped.
- **§2 What was implemented** — soft-threshold admission branch, `routing_tier` /
  `degraded_notice` wiring, hard-exhaustion `period_reset` threading, persistence of
  `ai_request.routing_tier`.
- **§3 Files to review** — this slice's `src/quota-do/`, `src/admission/`, `src/soft-threshold/`,
  journal/adapter extensions, this slice's test file, and `contracts/*` only.
- **§4 Prerequisites** — omitted; `npx vitest run` against this slice's test file is sufficient.
- **§5 Run the automated suite** — slice-only
  `npx vitest run test/soft-threshold-routing.test.ts`; no full-suite `npm test`, no combined
  prior-slice counts.
- **§6 Inspect the changes** — grep `degraded`, `routing_tier`, `period_end` / `period_reset`,
  focused Vitest file, frozen contracts.
- **§7 Manual validation** — omitted; CI is the only verification path (DP-3; no user-facing
  surface beyond the gateway outcomes the suite asserts).

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── quota-do/
│   │   └── index.ts              # MODIFIED — soft-threshold branch on admit; period_end on exhaustion
│   ├── admission/
│   │   └── index.ts              # MODIFIED — map degraded + periodReset; expose on AdmissionResult
│   ├── soft-threshold/
│   │   └── index.ts              # NEW — routing_tier / degraded_notice derivation from admission
│   ├── router/
│   │   └── index.ts              # CONSUMED unchanged — already matches rules[].match.tiers
│   ├── journal/
│   │   └── index.ts              # MODIFIED (extension) — RequestRowInput.routingTier → ai_request.routing_tier
│   ├── adapter.ts                # MODIFIED (extension) — optional degraded_notice on accepted data
│   └── errors.ts                 # CONSUMED unchanged — supplementaryFieldsForCode(periodReset)
└── test/
    └── soft-threshold-routing.test.ts   # NEW — T1–T7 integration (Pipeline / spy)
```

**Structure Decision**: Soft-threshold *detection* stays inside the Quota DO admission handler
(§4.3.3) so it rides the existing single round trip. Gateway-internal signal mapping
(`routing_tier` / `degraded_notice`) lives in a small new `src/soft-threshold/` module — one
implementation, no interface (D-15) — so F4 Freezes bind to a named artifact without inventing a
second DO call or rewriting D2/C3 cores. D2's `src/router/` is called with
`RouterContext.routingTier` and is not rewritten. C3's `createRequestRow` and A6's `accepted` event
are extended only to carry Freezes fields. The Spec Kit template's `frontend/` / `backend/` trees
are unused; the Worker source tree in `ai-platform/` is the relevant one (delivery plan §7.1).
Tests compose admission → soft-threshold signal → router → journal persist → accepted/error wire
with seeded DO counters (Clarification), mirroring C3/B4's stage-function integration style without
requiring a full POST orchestrator.

## Consumes Binding

| Consumes entry (from spec) | Bound to (existing module / file / type) |
| --- | --- |
| **B4** — per-installation Quota DO; stage-8 admission RPC (four questions + remaining budget); separate credit RPC; entitlement snapshot via config cache (incl. soft threshold); hard budget exhaustion → `quota_exhausted` | `ai-platform/src/quota-do/index.ts` (`admissionRPC`, `EntitlementSnapshot.soft_threshold` / `period_bounds`, `PeriodCounters`); `ai-platform/src/admission/index.ts` (`runAdmission`, `mapEntitlementSnapshot`); frozen `specs/024-quota-do-admission/contracts/quota-do-rpc.md` (explicitly names F4 as extension consumer of remaining-budget fields) |
| **D2** — routing-policy-as-data; `rules[].match.tiers` (`standard` / `degraded`); selection reason / `routing_decision`; stateless routing | `ai-platform/src/router/index.ts` (`RouterContext.routingTier`, `RoutingTier`, `selectRoute` / chain selection); frozen `specs/029-provider-port-routing/contracts/routing-decision.md` |
| **A5** (transitive) — `entitlement.soft_threshold`; nullable `ai_request.routing_tier` / `routing_decision` columns | `ai-platform/migrations/20260731120000_platform_schema.sql` + `schema.snap.sql`; `specs/019-ai-context-keys-d1-config/data-model.md` §2.6 — F4 writes `routing_tier` only; no schema change |
| **C3** (transitive) — request-row journal writer | `ai-platform/src/journal/index.ts` (`createRequestRow`, `RequestRowInput`) — F4 extends by populating `routing_tier`; does not rewrite stage-9 timing, transitions, post-response, or get-request; frozen `specs/027-journal-writer-get-request/contracts/journal.md` |
| **A2** (transitive) — `quota_exhausted` taxonomy + supplementary `period_reset` | `ai-platform/src/errors.ts` (`supplementaryFieldsForCode`, `SupplementaryFieldInput.periodReset`) — F4 populates `periodReset` from entitlement period end; does not rename to `reset_at` |
| **A6** (transitive) — accepted-event / error wire surface | `ai-platform/src/adapter.ts` (SSE `accepted` framing) — F4 extends `accepted.data` with optional `degraded_notice`; does not rewrite vocabulary or one-terminal-event invariant; frozen `specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md` |

Every **Consumes** entry binds to an existing implementation. F4 **extends** B4 admission response,
C3 request-row input, and A6 accepted-event data with Freezes-named fields only — it does not rewrite
frozen cores (delivery plan §2.3; B4 contract §10 Consumers row for F4). Stop condition 2 is not
triggered for the previously escalated A5 schema gap (resolved: nullable `routing_tier` /
`routing_decision` present; F4 introduces no migration).

## Components Touched

| §4 component | What F4 changes | Why |
| --- | --- | --- |
| **§4.3.3 Entitlement, quota, and rate control** | Soft-threshold `{ degraded: true }` branch on the existing admission allow path; hard-exhaustion response carries entitlement `period_end` for A2 `period_reset` | Primary — delivery plan §3.7 Canonical / Implements |
| **§4.3.7 Provider router and policy engine** | Supplies gateway-set `routing_tier` into D2's existing `RouterContext`; does not rewrite policy interpretation | Primary — delivery plan §3.7 Canonical / Implements; Done when requires degraded-tier selection |

**Reason for touching both:** Delivery plan §3.7 row F4 Canonical cell names both §4.3.3 and
§4.3.7 (plus sequence §8.8). Soft-threshold detection without the degraded routing path cannot
satisfy Done when ("downgrades routing to the capability's degraded tier rather than refusing");
routing alone cannot detect the soft threshold. These are one cohesive soft-threshold → degraded
routing path and cannot be tested apart (T1 asserts both admission `degraded` and degraded chain
selection).

**Wiring extensions (not additional §4 component ownership):**

- **§4.3.11 Journal writer (C3)** — populate existing `ai_request.routing_tier` only (FR-006).
- **§4.3.1 Protocol adapter (A6)** — optional `degraded_notice` on `accepted` data (FR-008).

Neither is listed in Implements as a component F4 owns; both are Freezes carriers already named in
Consumes. F4 does not take ownership of journaling or SSE framing.

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/quota-do/index.ts` | Modified — after hard-exhaustion check fails open, evaluate soft threshold; set `degraded: true` on `admitted`; on `quota_exhausted` include `period_end` from `entitlement.period_bounds.period_end` | FR-003, FR-005, FR-009, FR-010 |
| `ai-platform/src/admission/index.ts` | Modified — map DO `degraded` onto allow result; map `period_end` → failure carrying `periodReset` for A2 supplementary fields; still exactly one DO fetch | FR-001, FR-003, FR-004, FR-005, FR-009 |
| `ai-platform/src/soft-threshold/index.ts` | New — pure helpers: admission allow → `routing_tier`; soft allow → `degraded_notice`; ignore any client-supplied tier fields | FR-002, FR-006, FR-007, FR-008, FR-010 |
| `ai-platform/src/journal/index.ts` | Modified (extension) — `RequestRowInput.routingTier`; INSERT/bind `routing_tier` | FR-006 |
| `ai-platform/src/adapter.ts` | Modified (extension) — accepted-event builder accepts optional `degraded_notice` | FR-008 |
| `ai-platform/test/soft-threshold-routing.test.ts` | New — T1–T7 integration cases | Test Layout / SC-001..SC-004 |
| `ai-platform/vitest.workers.config.ts` | Modified — add `test/soft-threshold-routing.test.ts` to `include` | Test Layout |
| `specs/042-soft-threshold-degraded-routing/contracts/soft-threshold-admission.md` | New | Freezes → soft-threshold admission + hard-exhaustion period reset |
| `specs/042-soft-threshold-degraded-routing/contracts/degraded-routing-signal.md` | New | Freezes → `routing_tier`, degraded path, `degraded_notice` |
| `specs/042-soft-threshold-degraded-routing/quickstart.md` | New during Documentation task after verification | Project Structure → Documentation |

Every file traces to an `FR-###` or Freezes / Documentation mandate. No untraced file.
`ai-platform/src/router/index.ts` and `ai-platform/src/errors.ts` are consumed unchanged (no plan
row as modified).

## Test Layout

Per architecture §13.5 **Pipeline tests** and delivery plan §3.11.6 row F4 (**Integration**), with
spy where the invariant is work *not* done (§3.10). All seven named cases live in one workers-pool
file so Miniflare can host the real Quota DO binding and D1 for journal assertions. Fixtures seed
Quota DO counters / entitlement snapshot into the target region before the request under test
(Clarification Session 2026-08-02).

| # | Named test (spec Test plan) | Layer (§13.5) | File |
| --- | --- | --- | --- |
| 1 | `soft_threshold_selects_degraded_target` | Pipeline tests (Integration) | `ai-platform/test/soft-threshold-routing.test.ts` |
| 2 | `hard_exhaustion_quota_exhausted_admin_path_no_lock` | Pipeline tests (Integration) | `ai-platform/test/soft-threshold-routing.test.ts` |
| 3 | `below_threshold_traffic_unaffected` | Pipeline tests (Integration) | `ai-platform/test/soft-threshold-routing.test.ts` |
| 4 | `soft_threshold_tier_not_accepted_from_client` | Pipeline tests (Integration) | `ai-platform/test/soft-threshold-routing.test.ts` |
| 5 | `soft_threshold_persists_routing_tier` | Pipeline tests (Integration) | `ai-platform/test/soft-threshold-routing.test.ts` |
| 6 | `soft_threshold_no_second_quota_do_round_trip` | Pipeline tests (Integration — spy) | `ai-platform/test/soft-threshold-routing.test.ts` |
| 7 | `quota_exhausted_only_error_code_on_hard_exhaustion` | Pipeline tests (Integration) | `ai-platform/test/soft-threshold-routing.test.ts` |

**Coverage notes (§3.10):** Happy path of soft-threshold degrade (T1) and below-threshold (T3);
every error code this slice's soft/hard branches can emit — only `quota_exhausted` (T2, T7);
soft vs hard vs below branches (T1–T3); inherited prohibition of a second Quota DO round trip (T6
spy); client-injection prohibition (T4); persist path (T5). "Admin path" / no-lock (T2) asserts
gateway refusal carries populated `period_reset` (operator-addressable period end) and that
admission refusal performs no inference / no product-wide lock signal — E4 owns UI chrome (Out of
Scope).

Every named test places in a §13.5 layer — stop condition 3 not triggered.

## Sequencing

Tests and implementation land together, tests first or alongside — never after (skill rule).

1. **Frozen contracts first.** `contracts/soft-threshold-admission.md` and
   `contracts/degraded-routing-signal.md` constrain the extensions; later slices bind to these
   artifacts (delivery plan DP-4 / §2.3).
2. **Quota DO soft/hard admission extension + seeded DO fixtures.** Soft-threshold branch and
   `period_end` on exhaustion land in `quota-do/`; admission caller maps `degraded` /
   `periodReset`. Cases T1 (admission portion), T2, T3, T6, T7 turn green against seeded regions.
3. **Gateway signal module + router wiring.** `src/soft-threshold/` derives `routing_tier` /
   `degraded_notice`; compose with D2 router (unchanged). T1 (degraded chain) and T4 (ignore
   client tier) land.
4. **Journal + accepted-event extensions.** Persist `routing_tier` via C3 writer; emit
   `degraded_notice` on accepted. T1 (notice), T5 (persist), T3 (no notice below soft) complete.
5. **Vitest workers include + suite green.** Register `test/soft-threshold-routing.test.ts`; full
   T1–T7 green.
6. **Quickstart last.** `quickstart.md` after verification, documenting only this slice's files and
   commands.

## Complexity Tracking

> No Constitution Check violations. Nothing to justify here.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| — | — | — |
