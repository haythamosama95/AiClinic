# Implementation Plan: Entitle-and-grant operator path and live `context_required` self-heal (I4)

**Branch**: `ai/055-i4-entitle-grant-context-heal` | **Date**: 2026-08-07 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/055-entitle-grant-context-heal/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

I4 adds the operator-authenticated entitle-and-grant control mutation that activates a B2-enrolled installation (entitlement `pending` → `active` with budget fields admission already reads, plus `capability_grant` row(s) and `control_audit`) and hosts J2's `context_required` self-heal on the I3 live E2 submit path inside `FirstAiFeatureSurface._invoke`. It sits in Band I after B2, I3, and J2 (`Needs: B2, I3, J2`); completing it unlocks CP6 operability (`03-ai-platform-delivery-plan.md` §3.10 / §5 CP6) without absorbing Band G's commercial surface.

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`) for the control-plane entitle mutation; Dart (SDK `^3.11.5` as declared in `frontend/pubspec.yaml`) for production `ManifestRefreshPort` and live self-heal hosting on the first AI feature surface.

**Primary Dependencies**: B2 control-plane siblings under `ai-platform/src/control/` (`OperatorAuth` / `createSecretOperatorAuth`, `requireOperator`, `reject`/`ok`/`parseJsonBody`, `runControlBatch` / audit journaling, `dispatchControlRequest` / `isControlRoute` — Consumes, extended with one new route/handler only); A5 D1 tables `entitlement`, `capability_grant`, `control_audit` (schema unchanged); B3 `evaluateEntitlement` / B4 `EntitlementSnapshot` as read-only consumers of the rows I4 writes (not modified); I3 live Flutter host (`FirstAiFeatureSurface`, `AiFeatureHostDependencies`, `ai_page.dart`, `DiscoveryClient` — Consumes, composition only); J2 `ContextRequiredSelfHeal` + `ManifestRefreshPort` (`frontend/lib/core/ai/context_required_self_heal.dart` — Consumes, hosted not redefined). Clarification Session 2026-08-07: one combined `POST /control/installations/{id}/entitle` mutation; wire heal inside `FirstAiFeatureSurface._invoke` with production `ManifestRefreshPort` + existing resolver. No new pub packages, no Supabase schema/RPC changes, no plan catalogue / billing / usage-summary UI (FR-007; Band G).

**Storage**: Platform D1 only for entitle-and-grant writes into existing A5 columns on `entitlement` (`period_start`, `period_end`, `request_quota`, `token_budget`, `cost_budget`, `allowed_capabilities`, `soft_threshold`, `status`) plus `capability_grant` and `control_audit`. **No new migration** — Key Entities are N/A; field shapes consumed unchanged from §7.3 / A5. Flutter side: ephemeral client manifest refresh only (no new clinic tables). Note: §7.3 / T2 prose name `max_cost_class`; the frozen A5 `entitlement` table and B4 `EntitlementSnapshot` do **not** persist or load that field today, and the live Worker injects router `entitlementMaxCostClass` separately. Per Done when / FR-002 / Out of Scope (do not reimplement B3/B4), I4 writes the budget fields admission **already** reads from D1 and does not add a `max_cost_class` column or change router composition.

**Testing**: Workers integration for T1–T4 (`npx vitest run --config vitest.workers.config.ts` against this slice's entitle test file; Miniflare D1 + fake/`SELF.fetch` operator auth — same pattern as B2 `control.test.ts`). Flutter widget + integration for T5–T8 (`flutter test` against this slice's live self-heal widget file; spies for heal / refresh / SDK — live Worker not required for the Flutter suite). Layers per delivery plan §3.12.9 I4 and §13.5. Suite joins CI permanently (§3.11). When extending workers harnesses that seed entitlement for guard paths, keep I1's pattern of applying the I2 kill_switch migration in `beforeAll` where that suite already does so — do not regress it.

**Target Platform**: `ai-platform/` Cloudflare Worker (control-plane mutation) and Flutter Windows desktop client (`frontend/`) for live self-heal hosting. Gateway remains additive, non-primary (§14).

**Project Type**: Band I live-composition slice spanning Worker control plane + Flutter host wiring. Not a new deployable; not Band G.

**Performance Goals**: Control-plane entitle is operator-rare (no latency budget). Live self-heal adds at most one client-driven refresh → resolve → resubmit; no second Quota DO round trip, no second D1 insert on the guard path, no second R2 object per request (§6.1, §7.5, §13.6; delivery plan §6.4). No per-request server-side healing session (§4.4, §9.7; §8.4).

**Constraints**:
- One combined operator action `POST /control/installations/{installation_id}/entitle` writing entitlement economics + `capability_grant` row(s) + `control_audit` in one mutation (Clarification Q1; FR-002–FR-004).
- Operator identity only — non-operator rejected with existing B2 control rejection shape; no entitlement/grant mutation (FR-001, FR-006; T4).
- Pending enroll remains `pending` / zeroed / empty until entitle; stage 3 fails closed (`status !== "active"` → `ai_disabled` path) until activated (FR-005; T3).
- Soft threshold on write must stay in `[0, 1]` via existing `isSoftThresholdFraction` / `coerceSoftThreshold` contract (B2 lifecycle comment; F4).
- Capability grant/gate at `installation` or `plan` scope only for this activate path; global deprecate/retire remain J1 (Out of Scope).
- No plan catalogue, billing period close, or usage-summary UI (FR-007; OD-15; Band G).
- Wire `ContextRequiredSelfHeal` inside `FirstAiFeatureSurface._invoke` (surface calls heal instead of raw `sdk.invoke`); inject production `ManifestRefreshPort` with the surface's existing resolver (Clarification Q2; FR-008).
- One automatic resubmission; second `context_required` surfaces request reference; no third attempt; conversational never takes the path (FR-009–FR-010; T5–T8; Consumes J2).
- Do not modify Consumes contracts (B2 lifecycle/auth, I3 mint/submit/discovery UX, J2 heal bound) — delivery plan §2.3. Do not reimplement I2 discovery filtering or I1 Worker orchestration.
- No prompt/provider/model identifiers in Flutter (R-12; delivery plan §6.4).

**Scale/Scope**: Two §4 component groups (§4.5 Control plane + §4.1 Client-side feature-surface hosting — see Components Touched). Roughly: one entitle handler + barrel/dispatch wiring, one production `ManifestRefreshPort`, surface/host/hub composition hooks, one workers integration test file (T1–T4), one Flutter widget test file (T5–T8), one quickstart. Ten FRs. Eight named tests. Roughly 18–22 tasks — under the ~25-task ceiling (delivery plan §6.3 / plan stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — infrequent
      operator entitle of clinic-scale installations; one client self-heal round trip; no
      entitlement marketplace or fleet orchestration (constitution I; OD-15; Band G deferred;
      spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — one new `/control` mutation on the
      existing Worker plus Flutter composition of an existing heal sibling; no new deployable.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — I4
      touches `ai-platform/` (control-plane D1 writes) and `frontend/` (host J2 on the live
      submit path). It does not touch `backend/` for entitlement writes; self-heal key
      resolution stays under caller RLS via E3. **§14 acknowledgement:** the Worker is an
      additive, non-primary component with no domain logic, no business data, and no write
      path into Supabase; AI stays optional (A11).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — clinic Supabase
      integrity is untouched. Platform D1 integrity for entitle writes is held by existing
      A5 PK/FK constraints plus `control_audit` with operator identity on every mutation
      (same B2 pattern). Context resolution for self-heal remains under caller RLS (E3).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — control mutations use operator identity
      (B2 `OperatorAuth`); audited via `control_audit`; live client path keeps Bearer AAT /
      E2 transport; soft-delete and clinic audit unchanged. (Operator scope is correctly
      above clinic-tenant scope for the control plane, as B2 established.)
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — pending
      entitlement fails closed for AI admission; first `context_required` recovers once;
      second surfaces the request reference; clinical work continues without AI (A11;
      constitution V; FR-005, FR-009).

## Project Structure

### Documentation (this feature)

```text
specs/055-entitle-grant-context-heal/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify (authoritative)
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — spec `### Key Entities` is "Not applicable" (writes into existing §7.3 / A5 shapes; no new entities).

`research.md` is **never** produced on this platform — the research is
`docs/architecture/ai-platform/01-ai-platform.md`.

`contracts/` is **not** produced — Band I freezes no new contract (Delivery Plan §3.10; §2.3;
spec **Freezes**: None). Later slices bind to the entitle handler / route on the existing B2
control surface and to the composed Flutter heal hosting, not to a new I4 wire file. Entitle
extends the `control_audit.action` vocabulary with an entitle action string (extension, not
rewrite of B2's frozen lifecycle vocabulary — §2.3).

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — I4 row of the delivery plan (§3.10) and §4.5 / §7.3 / §8.4 /
  §5.2; what the spec delivered; what the plan scoped; CP6.
- **§2 What was implemented** — combined `/control/installations/{id}/entitle` mutation;
  production `ManifestRefreshPort`; `FirstAiFeatureSurface._invoke` hosting
  `ContextRequiredSelfHeal`.
- **§3 Files to review** — only this slice's `ai-platform/src/control/` entitle touch points,
  this slice's workers test file, this slice's Flutter production refresh port +
  surface/host/hub composition, and this slice's Flutter widget test file.
- **§4 Prerequisites** — Node/workers pool for entitle tests; Flutter SDK for widget tests;
  `OPERATOR_*` bindings when exercising `SELF.fetch` control e2e (same as B2).
- **§5 Run the automated suite** — slice-only:
  `npx vitest run --config vitest.workers.config.ts test/entitle-grant.test.ts` and
  `flutter test test/widget/ai/live_context_required_self_heal_test.dart`; no full-suite
  `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — open entitle handler + dispatch route; open surface `_invoke`
  heal wiring and production `ManifestRefreshPort`; confirm Consumes modules not rewritten.
- **§7 Manual validation** — optional: operator `curl` entitle against local Worker then
  enrolled desktop `/ai` host for a stale-manifest self-heal (CP6 review); omit when the
  automated suite alone proves Done when for CI.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   └── control/
│       ├── entitle.ts                 # NEW — handleEntitle (combined entitlement + grant + audit)
│       ├── index.ts                   # MODIFIED — isControlRoute + dispatchControlRequest for /entitle
│       ├── types.ts                   # MODIFIED — EntitlePayload (and related) types only
│       ├── auth.ts                    # UNCHANGED (Consumes B2)
│       ├── http.ts                    # UNCHANGED (Consumes B2)
│       ├── audit.ts                   # UNCHANGED (Consumes B2 — may call writeAudit or batch inline)
│       ├── lifecycle.ts               # UNCHANGED (Consumes B2 — enroll/suspend/resume/rotate/delete)
│       ├── capability-lifecycle.ts    # UNCHANGED (Consumes J1 — global deprecate/retire)
│       └── …                          # UNCHANGED siblings
├── vitest.workers.config.ts           # MODIFIED — include this slice's entitle test file
└── test/
    └── entitle-grant.test.ts          # NEW — T1–T4 Workers integration

frontend/
├── lib/
│   ├── core/
│   │   └── ai/
│   │       ├── context_required_self_heal.dart        # UNCHANGED (Consumes J2)
│   │       ├── discovery_client.dart                  # UNCHANGED (Consumes I3)
│   │       ├── discovery_manifest_refresh_port.dart   # NEW — production ManifestRefreshPort
│   │       ├── ai_client_sdk.dart                     # UNCHANGED (Consumes E2 via I3/J2)
│   │       └── context_resolver.dart                  # UNCHANGED (Consumes E3)
│   └── features/
│       └── ai/
│           ├── surface/first_ai_feature_surface.dart  # MODIFIED — _invoke uses ContextRequiredSelfHeal
│           ├── host/ai_feature_host_page.dart         # MODIFIED — pass ManifestRefreshPort through deps
│           └── presentation/pages/ai_page.dart        # MODIFIED — construct production refresh port
└── test/
    └── widget/
        └── ai/
            └── live_context_required_self_heal_test.dart  # NEW — T5–T8 Flutter widget + integration
```

**Structure Decision**: Entitle lands as a new sibling under `ai-platform/src/control/` (same
pattern as `lifecycle.ts` / `cohort.ts`) and is wired only through the existing barrel
`dispatchControlRequest` / `isControlRoute` — B2 lifecycle handlers stay untouched. Flutter
production `ManifestRefreshPort` lives beside I3's `DiscoveryClient` under `core/ai/` and is
injected into `FirstAiFeatureSurface` so `_invoke` calls `ContextRequiredSelfHeal.invoke`
instead of raw `sdk.invoke` (Clarification Q2), without rewriting J2's heal bound or I3's
mint/submit adapters.

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How I4 binds to it |
| --- | --- | --- |
| **B2 — Control-plane enrollment and installation lifecycle** (operator identity; five lifecycle actions; enroll write set; every mutation journals `control_audit`; enroll leaves `entitlement` `pending` with zeroed economics) | `ai-platform/src/control/` — `auth.ts` (`createSecretOperatorAuth`), `http.ts` (`requireOperator`, `reject`, `ok`, `parseJsonBody`, `runControlBatch`), `lifecycle.ts` (enroll/suspend/resume/rotate/delete), barrel `index.ts` (`dispatchControlRequest` / `isControlRoute`); frozen artifact `specs/022-control-plane-enrollment/contracts/control-plane.md`; Worker `/control` wiring in `worker.ts`. Spec/plan: `specs/022-control-plane-enrollment/`. | I4 **extends** the same operator-authenticated surface with one combined `/entitle` handler that updates the pending `entitlement` row, writes `capability_grant`, and journals `control_audit`. It does **not** rewrite enroll, suspend, resume, rotate, delete, or operator-auth. |
| **I3 — Live client invoke on the first AI feature surface** (production AAT mint + HTTPS submit on E4 host; E3 key resolution; stable idempotency; SSE to terminal; provisional/degraded UX) | `frontend/lib/core/ai/supabase_aat_mint_port.dart`, `https_submit_port.dart`, `discovery_client.dart`; `frontend/lib/features/ai/surface/first_ai_feature_surface.dart`; `host/ai_feature_host_page.dart` (`AiFeatureHostDependencies`); `presentation/pages/ai_page.dart`. Spec/plan: `specs/054-live-client-invoke/`. | I4 **hosts** J2 self-heal on that live submit path by composing heal + production `ManifestRefreshPort` into the existing surface/host/hub. It does **not** reimplement mint, discovery filtering, Worker orchestration, or E4 provisional/degraded UX contracts. |
| **J2 — `context_required` self-healing round trip** (one refresh → resolve → resubmit once with same idempotency key; second surfaces reference; conversational excluded) | `frontend/lib/core/ai/context_required_self_heal.dart` (`ContextRequiredSelfHeal`, `ManifestRefreshPort`, `InteractionMode`); optional C2 fields on `PlatformHttpException` in `ports.dart`. Spec/plan: `specs/049-context-required-self-healing/`. | I4 **constructs and injects** production `ManifestRefreshPort` and calls `ContextRequiredSelfHeal.invoke` from `FirstAiFeatureSurface._invoke`. It does **not** redefine the C2 payload, one-resubmission bound, or conversational exclusion. |

No consumed entry lacks an implementation. No consumed **contract** is rewritten (delivery plan §2.3). Stop condition 2 is not triggered.

## Components Touched

| §4 component | What I4 changes | Behaviour added? |
| --- | --- | --- |
| §4.5 Control plane | Realises the **Entitlement management** / **Capability availability** activate-and-grant path as one combined `/entitle` mutation on the existing operator surface; journals `control_audit` with operator identity. Does not rewrite Installation lifecycle (B2) or global deprecate/retire (J1). | Yes — enrolled installations can leave `pending` and become admissible for stages 3/8. |
| §4.1 Client-side components (AI Feature Surfaces hosting) | **Composition only** — `FirstAiFeatureSurface._invoke` hosts J2's `ContextRequiredSelfHeal`; production `ManifestRefreshPort` (DiscoveryClient-backed) injected with the surface's existing resolver. Does not change SDK transport rules or J2 heal semantics. | Yes — live E2 submit path performs §8.4 one-shot self-heal (Delivery Plan §3.10 Done when; CP6 client half). |

**Written reason (more than one §4 component):** Delivery plan §3.10 row **I4** Canonical is `§4.5, §7.3, §8.4, §5.2` and Done when explicitly requires **both** (a) operator entitle-and-grant writes and (b) hosting J2 self-heal on the live submit path. Band I adds no new §4 component (DP-8 / §3.10); §7.3 is the D1 shape written by the control plane, and §8.4 / §5.2 are client behavioural contracts hosted on §4.1 Feature Surfaces. Touching §4.5 + §4.1 composition matches the slice row; neither half alone satisfies Done when / CP6.

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/control/entitle.ts` | Created | FR-001–FR-006 — combined operator entitle: activate entitlement budget fields admission already reads, write `capability_grant` row(s), journal `control_audit` with operator identity; reject non-operator. |
| `ai-platform/src/control/types.ts` | Modified | FR-002, FR-003 — `EntitlePayload` (period bounds, quotas/budgets, soft threshold, allowed capabilities, grant list) for the combined mutation. |
| `ai-platform/src/control/index.ts` | Modified | FR-001, FR-006 — extend `isControlRoute` / `dispatchControlRequest` for `POST /control/installations/{id}/entitle` without altering lifecycle routes. |
| `ai-platform/vitest.workers.config.ts` | Modified | SC-001–SC-004 — include this slice's entitle integration test file in the workers pool. |
| `ai-platform/test/entitle-grant.test.ts` | Created | SC-001–SC-004 — named tests T1–T4 (Integration). |
| `frontend/lib/core/ai/discovery_manifest_refresh_port.dart` | Created | FR-008 — production `ManifestRefreshPort` using I3 `DiscoveryClient` (refresh + `interactionModeFor` from cached manifests). |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | Modified | FR-008–FR-010 — `_invoke` calls `ContextRequiredSelfHeal.invoke` instead of raw `sdk.invoke`; inject refresh port + existing resolver (Clarification Q2). |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | Modified | FR-008 — pass `ManifestRefreshPort` through `AiFeatureHostDependencies` into the surface (minimal composition hook). |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | Modified | FR-008 — construct production `ManifestRefreshPort` beside existing discovery composition. |
| `frontend/test/widget/ai/live_context_required_self_heal_test.dart` | Created | SC-005–SC-006 — named tests T5–T8 (Flutter). |
| `specs/055-entitle-grant-context-heal/quickstart.md` | Created (implement phase) | — template-mandated review surface; sections named above. |

Every code file traces to an `FR-###`. No file is created for an unstated requirement. Consumed B2 lifecycle handlers, J2 heal module sources, and I3 mint/submit/discovery adapters stay unchanged aside from the listed composition hooks.

## Test Layout

The spec's `### Test plan` names eight tests (delivery plan §3.12.9 I4; §13.5 Workers
integration + Flutter / client contract). Place them as follows:

| Spec Test plan name | Test id | File | §13.5 layer | Asserts (FR / SC) |
| --- | --- | --- | --- | --- |
| `entitle_activate_writes_entitlement_grant_and_audit` | T1 | `ai-platform/test/entitle-grant.test.ts` | Workers integration | FR-002–FR-004 / SC-001 — operator entitle writes entitlement + `capability_grant` + `control_audit` with operator identity |
| `entitle_sets_budget_fields_admission_reads` | T2 | `ai-platform/test/entitle-grant.test.ts` | Workers integration | FR-002 / SC-002 — writes period bounds, request quota, token/cost budget, soft threshold, allowed capability set; status → `active` (A5 columns / `EntitlementSnapshot`; see Technical Context note on `max_cost_class`) |
| `pending_enroll_fails_entitlement_until_activated` | T3 | `ai-platform/test/entitle-grant.test.ts` | Workers integration | FR-005 / SC-003 — pending enroll still fails stage-3 entitlement until entitle runs |
| `entitle_non_operator_rejected` | T4 | `ai-platform/test/entitle-grant.test.ts` | Workers integration | FR-006 / SC-004 — non-operator rejected; no entitlement/grant mutation |
| `live_self_heal_refreshes_resolves_resubmits_once_same_key` | T5 | `frontend/test/widget/ai/live_context_required_self_heal_test.dart` | Flutter widget + integration | FR-008 / SC-005 — live surface path refreshes, resolves, resubmits once with same idempotency key |
| `live_self_heal_second_context_required_surfaces_reference` | T6 | `frontend/test/widget/ai/live_context_required_self_heal_test.dart` | Flutter widget + integration | FR-009 / SC-006 — second `context_required` surfaces request reference |
| `live_self_heal_no_automatic_third_attempt` | T7 | `frontend/test/widget/ai/live_context_required_self_heal_test.dart` | Flutter widget + integration | FR-009 / SC-006 — no automatic third attempt |
| `live_self_heal_conversational_never_takes_path` | T8 | `frontend/test/widget/ai/live_context_required_self_heal_test.dart` | Flutter widget + integration | FR-010 / SC-006 — conversational never takes §8.4 path on live submit host |

Every named test from the spec is placeable in §13.5. No named test is orphaned.

## Sequencing

1. **Tests first (or alongside)** — add `entitle-grant.test.ts` (T1–T4) and `live_context_required_self_heal_test.dart` (T5–T8) failing red against missing handler / unwired heal (never after implementation).
2. **Entitle handler** — `entitle.ts` + `EntitlePayload` types; soft-threshold validation; D1 batch update entitlement + insert grant(s) + `control_audit` (FR-001–FR-006).
3. **Control dispatch** — wire `/entitle` into `isControlRoute` / `dispatchControlRequest`; include test file in `vitest.workers.config.ts`.
4. **Turn entitle tests green** — T1–T4 (including pending boundary via `evaluateEntitlement` or equivalent stage-3 check against D1 state).
5. **Production ManifestRefreshPort** — `discovery_manifest_refresh_port.dart` backing J2's port with I3 `DiscoveryClient` (FR-008).
6. **Live host wiring** — inject refresh port through host deps; `FirstAiFeatureSurface._invoke` uses `ContextRequiredSelfHeal` with existing resolver; hub constructs production port (Clarification Q2; FR-008–FR-010).
7. **Turn Flutter tests green** — T5–T8 against spies/fakes on the live surface composition.
8. **Verification** — slice-only workers vitest + flutter test commands above; confirm Consumes modules not rewritten; keep I1 kill_switch migration `beforeAll` intact where that suite already applies it.
9. **Documentation** — write `quickstart.md` per sections above.

## Complexity Tracking

> No constitution violations requiring justification. Empty by design.
