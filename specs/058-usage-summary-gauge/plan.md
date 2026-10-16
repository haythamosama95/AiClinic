# Implementation Plan: Usage summary endpoint and in-app gauge (G3)

**Branch**: `ai/058-g3-usage-summary-gauge` | **Date**: 2026-09-11 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/058-usage-summary-gauge/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

G3 freezes an installation-authenticated usage-summary read that answers current-period credits consumed against budget live from the Quota Durable Object and prior-period credits from `usage_rollup`'s quota-weight aggregate, and it extends the E4 AI Feature Surface with a simple consumed-versus-budget gauge. It sits in Band G after G2 and E4 (`Needs: G2, E4`); G4 invoices stay out of scope and the operator quota inspect route stays operator-only.

## Technical Context

**Language/Version**: TypeScript 5.9 (`ai-platform/package.json`) targeting the Cloudflare Worker and `cloudflare:workers` Durable Object (Node `>=22` for the Vitest / Wrangler harness). Dart SDK `^3.11.5` (`frontend/pubspec.yaml`) for the Flutter gauge and occasional GET client.

**Primary Dependencies**: G2 Quota DO live counters `creditsUsed` against snapshot `credit_budget` (`ai-platform/src/quota-do/index.ts` `PeriodCounters`, `EntitlementSnapshot`, `inspectRPC`); E4 AI Feature Surfaces, AI availability flag, and degraded mode (`frontend/lib/features/ai/`); I2 enrolled-key verifier and installation GET pattern (`EnrolledKeyVerifier`, `GET /v1/capabilities`); F3 `usage_rollup` production (`ai-platform/src/rollup/index.ts`) extended under Delivery Plan §2.3 with `SUM(usage_event.quota_weight)` — cadence, retention, purge, and reconciliation unchanged. Occasional Flutter GET follows `DiscoveryClient` in `frontend/lib/core/ai/`. No new npm or pub packages. No Supabase write path. No payment-provider integration.

**Storage**: Platform D1 only — forward-only column `usage_rollup.quota_weight` (pre-aggregated `SUM(usage_event.quota_weight)`). No new table. Quota DO inspect is a read of G2 state; this slice does not persist a new DO field. No R2 write. No clinic Supabase write.

**Testing**: Workers integration + Flutter widget (spy) per delivery plan §3.12.10 row G3 and architecture §13.5 (Pipeline tests for the Worker handler; Flutter widget suite for the gauge). Six named Worker cases in `ai-platform/test/usage-summary.test.ts`. Three named Flutter cases in `frontend/test/widget/ai/usage_gauge_test.dart`. Suites join CI permanently (§3.11).

**Target Platform**: `ai-platform/` Cloudflare Worker (usage-summary read + rollup aggregation extension) and Flutter Windows desktop (`frontend/`, E4 AI Feature Surface). Gateway remains additive, non-primary (§14). No `backend/` code.

**Project Type**: Band G commercial-surface slice that touches the Worker and Flutter because delivery plan §3.13 row G3 Done when requires both the installation-facing read and the in-app gauge. Not a request-path pipeline stage. Not a new §4.3 component.

**Performance Goals**: Occasional read, off the request-path latency budget (§7.6; FR-012). One Quota DO inspect round trip on this read for live current-period counters; one D1 select of `usage_rollup` for history. MUST NOT scan `usage_event`. MUST NOT add a second Quota Durable Object round trip or a second R2 object on the inference request path (§7.5, §13.6, delivery plan §6.4). No per-request server-side state. No retry or cache layer.

**Constraints**:
- Credits-only response: no provider prices, no token actuals, no cost actuals (FR-004). G2 counter names `creditsUsed` / `credit_budget` keep their meanings.
- Live current period from the Quota DO; prior periods from `usage_rollup.quota_weight`; those answers MUST come from different places (FR-002, FR-013).
- Delivery Plan §2.3 extension of F3's existing `usage_rollup` row: add `quota_weight` and extend the SUM; do not change tokens/cost/`request_count` meanings; do not introduce a table; do not rewrite F3 cadence/retention/purge/reconciliation.
- Installation-facing handler with Bearer AAT (same verifier as I2). MUST NOT expose `GET /control/installations/:id/quota` to installations. MAY reuse `inspectRPC` internally for live current-period counters.
- Unauthenticated caller → closed taxonomy code `unauthenticated` (spec "taxonomy unauthorized"; A2 closed set; same mapping I2 uses). `quota_exhausted` remains G2 admission and is not emitted here.
- Flutter: extend E4 AI Feature Surface; hide gauge for non-enrolled with no network probe; unreachability is a normal state, not an error dialog (A11). Do not rewrite E4 draft/accept/discard, provisional content, or request-reference display.
- No prompt text, provider name, or model identifier in the Flutter client (FR-007; R-12).

**Scale/Scope**: Two surfaces named by delivery plan §3.13 Done when — Worker usage-summary read and Flutter gauge — with an explicit reason in Components Touched. Thirteen FRs. Nine named tests. One D1 column extension. Roughly 18–22 tasks — under the ~25-task ceiling (delivery plan §6.3 / plan stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — a
      simple credits-versus-budget gauge in the platform's own credit unit, no
      analytics dashboard, no payment-provider integration (constitution I; spec
      Clinic Fit; A15).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — one Worker read handler plus
      one Flutter gauge inside the existing `ai-platform/` and `frontend/` deployables;
      no new service or store.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated —
      G3 touches `ai-platform/` (usage-summary read + `usage_rollup` column) and
      `frontend/` (gauge). It does not touch `backend/`. **§14 acknowledgement:** the
      Worker is an additive, non-primary component with no domain logic, no business
      data, and no write path into Supabase. The usage-summary read is platform Quota
      DO counters and `usage_rollup`, not clinic business data; the gauge is additive
      client UI (A15 constitution check).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — clinic
      Supabase integrity is untouched. This slice writes no clinic table. The only D1
      write is F3's existing rollup job, extended with a SUM field (FR-013); the
      usage-summary path itself is read-only.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — the endpoint is installation-authenticated
      (Bearer AAT, same enrolled-key verifier as I2); unauthenticated callers are
      rejected; the operator quota inspect route stays operator-only; reads are
      scoped to the authenticated installation's DO instance and `usage_rollup` rows.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — non-enrolled
      hides the gauge with no probe; platform unreachability is a normal state, not an
      error dialog; no AI failure, including usage-summary unreachability, blocks a
      clinical workflow (A11; FR-008, FR-009, FR-010). Consumed-versus-budget on the
      gauge, including when consumed meets budget, is not an error dialog and does not
      hard-lock clinical work.

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component
with no domain logic, no business data, and no write path into Supabase. G3 adds an
installation-facing credits-only read of Quota DO counters and `usage_rollup` plus a
Flutter gauge; it never writes clinic data and never hard-locks non-AI workflows.

## Project Structure

### Documentation (this feature)

```text
specs/058-usage-summary-gauge/
├── plan.md                         # This file
├── spec.md                         # /ai-platform-specify + /ai-platform-clarify (authoritative)
├── data-model.md                   # Phase 1 — usage_rollup.quota_weight extension (FR-013)
├── contracts/
│   └── usage-summary.md            # Freezes: installation-facing GET, credits-only JSON
└── quickstart.md                  # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` **is** produced — this slice extends the existing D1 `usage_rollup` row with
the quota-weight aggregate (spec Key Entities; FR-013). It introduces no table. A5's
`specs/019-ai-context-keys-d1-config/data-model.md` and F3's
`specs/041-support-retention-rollups/contracts/usage-rollup-reconciliation.md` are **not**
rewritten (delivery plan §2.3).

`research.md` is **never** produced on this platform — the research is
`docs/architecture/ai-platform/01-ai-platform.md`.

`contracts/` is produced because **Freezes** entries have a wire shape later slices’
**Consumes** must bind to (V4 renders the same consumed-versus-budget read): path, Bearer
AAT, credits-only JSON, taxonomy `unauthenticated`. The in-app gauge and degraded-mode
application are behavioural and bind to the Flutter modules under `frontend/lib/features/ai/`,
not to additional prose contract files.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — G3 row of the delivery plan (§3.13) and §7.6 / §4.1 / A11 /
  A15; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — installation-facing `GET /v1/usage`; credits-only payload;
  `usage_rollup.quota_weight` SUM extension; Flutter consumed-versus-budget gauge; hide
  without probe; unreachable as a normal state.
- **§3 Files to review** — only this slice's `src/usage-summary/`, rollup SUM extension,
  forward migration, Worker route, Flutter `core/ai` GET client and `features/ai` gauge,
  this slice's named tests, `data-model.md`, and `contracts/usage-summary.md`.
- **§4 Prerequisites** — omitted; slice-only vitest and `flutter test` are sufficient.
- **§5 Run the automated suite** — slice-only:
  `npx vitest run --config vitest.workers.config.ts test/usage-summary.test.ts`
  (G3's six named Worker tests) and `flutter test test/widget/ai/usage_gauge_test.dart`
  (G3's three named Flutter tests). No full-suite `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — grep `GET /v1/usage` and `quota_weight`; read the contract
  and data-model; confirm operator `quota-inspect.ts` is not opened to installations; confirm
  Consumes G2/E4 modules are not rewritten.
- **§7 Manual validation** — optional: enrolled host shows the gauge; non-enrolled hides it.
  Omit if CI is the sole verification path (DP-3).

### Source Code (repository root)

```text
ai-platform/
├── migrations/
│   └── 20260911180000_usage_rollup_quota_weight.sql  # NEW — usage_rollup.quota_weight
├── schema.snap.sql                                   # MODIFIED — pin the new column
├── src/
│   ├── usage-summary/
│   │   └── index.ts               # NEW — installation-facing GET handler (FR-001–FR-006, FR-011–FR-013)
│   ├── worker.ts                 # MODIFIED — dispatch GET /v1/usage
│   ├── rollup/
│   │   └── index.ts               # MODIFIED — extend SUM(usage_event.quota_weight) (FR-013)
│   ├── quota-do/index.ts          # UNCHANGED — Consumes G2; reuse inspectRPC internally
│   └── control/quota-inspect.ts   # UNCHANGED — stays operator-only
└── test/
    └── usage-summary.test.ts     # NEW — six named Workers integration cases

frontend/
├── lib/
│   ├── core/ai/
│   │   ├── discovery_client.dart  # UNCHANGED — pattern this slice's GET follows
│   │   └── usage_summary_client.dart  # NEW — occasional GET /v1/usage (FR-005, FR-012)
│   └── features/ai/
│       ├── surface/
│       │   ├── usage_gauge.dart   # NEW — consumed versus budget (FR-003, FR-007)
│       │   └── first_ai_feature_surface.dart  # UNCHANGED — do not rewrite draft/accept/discard
│       ├── host/
│       │   └── ai_feature_host_page.dart  # MODIFIED — compose gauge; apply E4 hide/unreachable
│       ├── availability/          # UNCHANGED — Consumes E4 flag
│       └── degraded/              # UNCHANGED — reuse E4 unreachable normal state
└── test/widget/ai/
    └── usage_gauge_test.dart     # NEW — three named Flutter widget (spy) cases
```

**Structure Decision**: The Worker handler is a new `src/usage-summary/` module wired from
`worker.ts` next to I2 `GET /v1/capabilities`, not from `src/control/` (that audience is
operator-only). Live current-period `creditsUsed` is read by reusing G2/`inspectRPC` on the
installation's Quota DO stub; `credit_budget` is the G2 snapshot name already served on
config-cache kind `"entitlements"` (`SELECT * FROM entitlement`) — the budget admission
already maps onto the DO — not a new DO field (do not modify Consumes G2). Prior periods are
a D1 select of `usage_rollup.quota_weight` for this installation excluding the current period
key (`periodFromIso(period_start)` → `YYYY-MM`). The Flutter GET lives in `core/ai` beside
`DiscoveryClient` (occasional Bearer AAT GET, injectable `http.Client`, no extra port
interface — D-15). The gauge lives under `features/ai/surface/` and is composed on the E4
host so enrollment/reachability already gated there apply; `FirstAiFeatureSurface` is not
rewritten. Spec Kit `backend/` placeholders are unused.

**Plan-time wire (clarify leftover, not a requirement):** architecture §5.5 names the
Usage summary surface without an HTTP path; spec Assumptions allow the plan to name the wire
without rewriting G2 counter semantics. Path `GET /v1/usage`. JSON field list in
`contracts/usage-summary.md`.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How G3 binds to it |
| --- | --- | --- |
| **G2 — Declared-weight credit debit in admission** (Quota DO current-period credit counters `creditsUsed` against entitlement snapshot `credit_budget`; token and cost counters remain reconciliation evidence, not usage-summary payload) | `ai-platform/src/quota-do/index.ts` (`PeriodCounters.creditsUsed`, `EntitlementSnapshot.credit_budget`, `inspectRPC`); config-cache kind `"entitlements"` already `SELECT *` so the loaded row includes `credit_budget` (`ai-platform/src/config-cache/index.ts`). Frozen artifacts: `specs/057-credit-debit/contracts/credit-rpc-debit.md`, `specs/057-credit-debit/contracts/credit-budget-admission.md`. | G3 **reads** live `creditsUsed` via `inspectRPC` (internal reuse of the DO inspect path). It **reads** `credit_budget` from the same entitlement snapshot G2 already maps. It does **not** debit, admit, set `degraded`, or change token/cost actuals. G2 contract files are not edited. Operator `src/control/quota-inspect.ts` is not opened to installations. |
| **E4 — First AI feature surface and degraded mode** (§4.1 AI Feature Surfaces; AI availability flag; degraded mode: non-enrolled hides without probing; unreachable is a normal state, not an error dialog; no AI failure blocks clinical work) | `frontend/lib/features/ai/surface/first_ai_feature_surface.dart`; `frontend/lib/features/ai/host/ai_feature_host_page.dart`; `frontend/lib/features/ai/availability/`; `frontend/lib/features/ai/degraded/ai_degraded_mode.dart` / `ai_degraded_view.dart`; frozen artifact `specs/038-first-ai-feature-surface/contracts/ai-availability-flag.md`. | G3 **extends** the E4 host with a simple gauge and **applies** the same hide-without-probe and unreachability rules. It does **not** rewrite draft/accept/discard, provisional content rules, or request-reference display. E4 contract files are not edited. |

No consumed entry lacks an implementation. No consumed **contract file** is rewritten (delivery plan §2.3). Stop condition 2 is not triggered.

**Transitive, not Consumes (extend under §2.3; do not rewrite):** F3 `usage_rollup` production (`ai-platform/src/rollup/index.ts`; A5 table `usage_rollup`). G3 adds column `quota_weight` and extends `aggregateUsageEvents` with `SUM(usage_event.quota_weight)`. F3 cadence, retention, purge, reconciliation flags, and equality-to-ledger for `request_count` / `tokens` / `cost` keep their meanings. F3's frozen contract file is not edited. I2 `EnrolledKeyVerifier` / `handleDiscoveryRequest` auth pattern is reused, not rewritten. A2 closed taxonomy: this slice's named diagnostic is `unauthenticated`.

## Components Touched

Two surfaces, with explicit reason (delivery plan §3.13 row G3 Done when):

1. **§4.1 AI Feature Surfaces** — Flutter simple gauge of consumed versus budget, hidden for a non-enrolled installation with no network probe, with platform unreachability as a normal state (Canonical §4.1; A11; A15).
2. **Gateway Worker — §5.5 Usage summary / §7.6 usage-summary read path** — installation-authenticated credits-only GET that reads live current-period counters from the Quota DO and prior periods from `usage_rollup`. This is not a new §4.3 pipeline stage and is not on the request-path I/O budget.

**Reason for both:** Delivery plan §3.13 row G3 Done when jointly requires (a) the authenticated installation usage-summary read on the Worker and (b) the Flutter gauge with hide-without-probe and unreachable-as-normal-state. Architecture places the read on the gateway (§7.6, §5.5) and the gauge on AI Feature Surfaces (§4.1). Touching both is the slice; it is not scope creep into G2 debit, G4 invoices, E4 draft/accept/discard, or the operator quota inspect route.

| §4 / named surface | Touched? | Reason |
| --- | --- | --- |
| §4.1 AI Feature Surfaces | **Extended** | Flutter gauge + degraded-mode application (Canonical; Done when *Client*) |
| §5.5 / §7.6 Usage summary read | **Created** | Installation-facing Worker endpoint (Done when *Endpoint*) |
| §4.3.3 Quota DO | **Not modified** | Consumes G2; reuses `inspectRPC` internally for live `creditsUsed` |
| §4.5 Control plane / operator quota inspect | **Not touched** | Stays operator-only (`src/control/quota-inspect.ts`) |
| §4.1 AI Client SDK / Context Resolver | **Not touched** | Occasional GET follows `DiscoveryClient` as a sibling in `core/ai`; does not rewrite invoke/SSE |
| §4.2 AI availability flag | **Not touched** | Consumes E4 store/read |

Stop condition 5 is satisfied: reason recorded; ~18–22 tasks.

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/migrations/20260911180000_usage_rollup_quota_weight.sql` | Created — `ALTER TABLE usage_rollup ADD COLUMN quota_weight INTEGER NOT NULL DEFAULT 0` | FR-013 |
| `ai-platform/schema.snap.sql` | Modified — pin `usage_rollup.quota_weight` | FR-013 |
| `ai-platform/src/rollup/index.ts` | Modified — `SUM(quota_weight)` in aggregation; INSERT/UPSERT the new column; `request_count` / `tokens` / `cost` unchanged | FR-013 |
| `ai-platform/src/usage-summary/index.ts` | Created — Bearer AAT; `inspectRPC` for live `creditsUsed`; entitlements snapshot for `credit_budget` and current period key; D1 `usage_rollup` for prior `quota_weight`; credits-only JSON; no `usage_event` scan | FR-001, FR-002, FR-004, FR-006, FR-011, FR-012, FR-013 |
| `ai-platform/src/worker.ts` | Modified — dispatch `GET /v1/usage` to the usage-summary handler | FR-001, FR-006, FR-012 |
| `ai-platform/test/usage-summary.test.ts` | Created — six named Workers integration cases (one spy) | Test Layout / SC-001–SC-003 |
| `frontend/lib/core/ai/usage_summary_client.dart` | Created — occasional `GET /v1/usage` with Bearer AAT, injectable `http.Client` (same shape as `DiscoveryClient`) | FR-005, FR-012 |
| `frontend/lib/features/ai/surface/usage_gauge.dart` | Created — simple consumed-versus-budget UI; no prompt/provider/model identifiers | FR-003, FR-007 |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | Modified — compose the gauge when enrolled and reachable; hide with no usage GET when non-enrolled; unreachable uses E4 normal state, not an error dialog | FR-003, FR-005, FR-008, FR-009, FR-010 |
| `frontend/test/widget/ai/usage_gauge_test.dart` | Created — three named Flutter widget (spy) cases | Test Layout / SC-004–SC-005 |
| `specs/058-usage-summary-gauge/data-model.md` | Created | FR-013; Key Entities |
| `specs/058-usage-summary-gauge/contracts/usage-summary.md` | Created | Freezes → endpoint + credits-only payload |
| `specs/058-usage-summary-gauge/quickstart.md` | Created (implement phase) | — template-mandated review surface; sections named above |

Every code file traces to an `FR-###`. No file is created for an unstated requirement. Consumed G2 DO admission/credit, E4 draft/accept/discard, operator quota inspect, and F3 cadence/retention/purge/reconciliation stay unchanged aside from the listed rollup SUM extension. No `backend/` file. No new table.

## Test Layout

The spec’s `### Test plan` names nine tests (delivery plan §3.12.10 G3; §13.5 Pipeline tests + Flutter widget suite). Place them as follows:

| Spec Test plan name | File | §13.5 layer | Asserts (FR / SC) |
| --- | --- | --- | --- |
| `usage_summary_current_period_live_from_quota_do` | `ai-platform/test/usage-summary.test.ts` | Pipeline (Workers integration) | FR-001 / SC-001 — authenticated installation: current-period `credits_used` / `credit_budget` match Quota DO `creditsUsed` against snapshot `credit_budget` |
| `usage_summary_prior_periods_from_usage_rollup` | `ai-platform/test/usage-summary.test.ts` | Pipeline (Workers integration) | FR-001, FR-013 / SC-001 — prior `credits_used` equals `usage_rollup.quota_weight`; SQL / spy shows no `usage_event` scan |
| `usage_rollup_carries_quota_weight_aggregate` | `ai-platform/test/usage-summary.test.ts` | Pipeline (Workers integration) | FR-013 / SC-001 — after rollup, `usage_rollup.quota_weight` equals `SUM(usage_event.quota_weight)` for that installation/period; `request_count`, `tokens`, and `cost` keep prior meanings |
| `usage_summary_live_and_historical_from_different_sources` | `ai-platform/test/usage-summary.test.ts` | Pipeline (Workers integration spy) | FR-002 / SC-001 — current-period answer is not served from `usage_rollup`; historical answer is not served from the Quota DO |
| `usage_summary_unauthenticated_taxonomy_unauthorized` | `ai-platform/test/usage-summary.test.ts` | Pipeline (Workers integration) | FR-006 / SC-002 — missing/invalid installation auth → taxonomy `unauthenticated` (HTTP 401); no credits body |
| `usage_summary_credits_only_no_prices_tokens_or_cost_actuals` | `ai-platform/test/usage-summary.test.ts` | Pipeline (Workers integration) | FR-004 / SC-003 — response JSON has no provider prices, no token fields, no cost actuals |
| `gauge_renders_consumed_versus_budget` | `frontend/test/widget/ai/usage_gauge_test.dart` | Flutter widget | FR-003, FR-005 / SC-004 — enrolled and reachable: gauge shows consumed versus budget |
| `gauge_non_enrolled_hides_with_no_network_probe` | `frontend/test/widget/ai/usage_gauge_test.dart` | Flutter widget (spy) | FR-008 / SC-005 — non-enrolled: gauge hidden; network spy shows no usage-summary GET |
| `gauge_unreachable_is_normal_state_not_error_dialog` | `frontend/test/widget/ai/usage_gauge_test.dart` | Flutter widget (spy) | FR-009, FR-010 / SC-005 — platform unreachability → E4 unreachable normal state, not an error dialog; clinical work not blocked |

Every named test from the spec is placeable in §13.5. No named test is orphaned. Inherited §6.4 prohibitions (no prompt/provider/model in the client; no second request-path DO/R2; no per-request state) are held by construction: this read is off the request path; the gauge lives under `features/ai/` (E1 guard already covers that tree). `quota_exhausted` is not emitted here.

**Prior-suite fixture note:** `quota_weight INTEGER NOT NULL DEFAULT 0` keeps existing `INSERT INTO usage_rollup (rollup_id, dimensions, request_count, tokens, cost)` statements green. Do not weaken F3 equality assertions. The new named test owns the quota-weight SUM.

## Sequencing

1. **Tests first (or alongside)** — add the six failing Worker describes and the three Flutter widget describes against missing `GET /v1/usage`, missing `quota_weight`, and missing gauge (never after implementation).
2. **D1 column** — forward-only `usage_rollup.quota_weight` + schema snapshot (FR-013).
3. **Rollup SUM extension** — `aggregateUsageEvents` and upsert include `SUM(quota_weight)`; tokens/cost/count unchanged (FR-013). Turn `usage_rollup_carries_quota_weight_aggregate` green.
4. **Usage-summary handler** — AAT verify; internal `inspectRPC` for live `creditsUsed`; entitlements snapshot for `credit_budget` and current period; D1 rollup select for prior periods; credits-only JSON (FR-001, FR-002, FR-004, FR-006, FR-013).
5. **Worker dispatch** — `GET /v1/usage` (FR-001, FR-012).
6. **Flutter GET + gauge** — `UsageSummaryClient` then `UsageGauge` composed on the E4 host (FR-003, FR-005, FR-007, FR-008, FR-009, FR-010).
7. **Turn tests green** — including the live-versus-historical spy, credits-only payload, no-probe spy, and unreachable-not-error-dialog.
8. **Verification** — slice-only vitest and `flutter test` commands above; confirm Consumes contract files, `quota-inspect.ts`, and E4 draft/accept/discard are untouched.
9. **Documentation** — write `quickstart.md` per sections above.

## Complexity Tracking

> No constitution violations requiring justification. Empty by design.
