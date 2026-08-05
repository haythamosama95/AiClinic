# Implementation Plan: First AI feature surface and degraded mode (E4)

**Branch**: `ai/038-e4-first-ai-feature-surface` | **Date**: 2026-08-02 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/038-first-ai-feature-surface/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

E4 lands the first user-visible **AI Feature Surfaces** in Flutter: live `prose` draft rendering with provisional styling, no commit affordance until terminal `completed`, explicit accept/discard under `advisory_display` (no F2 clinical write), request-reference display on every failure, and first-class degraded-mode states (non-enrolled, unreachable/offline, quota exhausted, AI unavailable) so AI never blocks clinical work (A11). It also freezes the clinic-side **AI availability flag** (enrolled + platform base URL). It sits last in Band E after E2 / E3 (`Needs: E2, E3`) and, with D4, is the CP3 falsification thread (delivery plan §3.6 / §5 CP3).

## Technical Context

**Language/Version**: Dart (SDK `^3.11.5` as declared in `frontend/pubspec.yaml`) for Feature Surfaces / host / widget suite; PostgreSQL / Supabase SQL for the AI availability flag (matching existing `public` INVOKER → `auth_internal` SECURITY DEFINER clinic RPCs and B1 `ai_internal.app_settings`).

**Primary Dependencies**: Flutter desktop client under `frontend/`; E2 AI Client SDK under `frontend/lib/core/ai/` (`AiClientSdk`, `sse_events`, `taxonomy`, ports — Consumes, not modified); E3 Context Resolver siblings under the same folder (`ContextResolver`, `contextRegistration` — Consumes, not modified); A2/A6 taxonomy and SSE terminal kinds via the SDK; A1 Worker `/health` for enrolled-only reachability; existing design-system AI semantic tokens (`AppSemanticColors.surfaceAi` / `textAi` / `borderAi`) as the draft styling tokens for T1 (Clarification Q3). First capability exercised by the surface: Open Decision 1 recommended default — non-clinical-record, `prose`, `advisory_display`; capability id pinned to the D1 fixture identity `clinic.visit_summary` (already used with those governance fields in prompt-composer/registry fixtures). Injectable availability / reachability / SDK / Resolver ports for widget spies (spec Assumptions). No Worker source changes, no new pub packages, no F2 acceptance RPC.

**Storage**: No D1 entities (spec Key Entities: not applicable). Clinic: AI availability flag as `ai_internal.app_settings` key `ai.availability` with `value_json` `{ enrolled, platform_base_url }`, readable via `public.get_ai_availability()` (see `contracts/ai-availability-flag.md`). Ephemeral surface state only — provisional prose is never persisted (FR-002, FR-005).

**Testing**: Flutter widget (spy) (delivery plan §3.11.5 row E4; DP-3). Named cases T1–T21 via `flutter test` against spies/fakes for enrollment flag, SDK streams, network, and persistence/export probes — no live provider inference required (spec Assumptions). Suite joins CI permanently (delivery plan §3.10). T20 additionally proves feature-surface sources under `frontend/lib/features/ai/` pass the E1 architecture guard (R-12). Mapping to §13.5: widget spy suite is the client Flutter test layer (DP-3); Architecture guard covers T20; Client contract tests remain E3’s.

**Target Platform**: Flutter Windows desktop client (`frontend/`) and local/clinic Supabase PostgreSQL (`backend/`). AI remains optional and additive; this slice adds no gateway stage.

**Project Type**: Dual-layer slice — Flutter AI Feature Surfaces + standalone host under `frontend/lib/features/ai/` (Clarifications Q1–Q2) plus clinic AI availability flag under `backend/supabase/migrations/`. Not a Worker slice (`ai-platform/` unchanged).

**Performance Goals**: None beyond ordinary client UI. E4 adds no Quota DO round trip, no D1 insert, and no R2 object on the Worker path; platform I/O budgets (§6.1, §7.5, §13.6) remain untouched. One enrolled-only reachability check against A1 `/health` is client-side and does not add platform write I/O.

**Constraints**: Provisional content visually draft; no commit/save/accept before `completed` (FR-003, FR-005; §6.4). Terminal validated payload authoritative — never assemble final answer from chunks (FR-004). Never persist/export/enter provisional into a clinical record (FR-002, FR-005). Every failure shows request reference (FR-006; §13.2). Branch on §5.4 codes and apply Client behaviour (FR-013) — hide features / hide affordance / show quota / show reference; no new taxonomy codes. Non-enrolled: hide affordances, zero platform probes (FR-009). Unreachable: normal state, not an error dialog (FR-011; A11). Accept under `advisory_display` acknowledges terminal payload only — no F2 write (FR-014). No prompt/provider/model identifiers (FR-015; R-12). Surfaces live under `features/ai/`; import SDK/Resolver from `core/ai` (Clarification Q1). Standalone host under `features/ai/` for tests + CP3 — not embedded in a production clinical screen (Clarification Q2). T1 asserts via stable test Key/Semantics + draft styling token (Clarification Q3).

**Scale/Scope**: Two §4 components with an explicit reason (see Components Touched): §4.1 AI Feature Surfaces and §4.2 AI availability flag. ~ten Flutter library files under `frontend/lib/features/ai/` (+ route wiring), one migration, one frozen contract, one widget test suite for T1–T21, one quickstart. Sixteen FRs. Twenty-one named tests. Roughly 20–24 tasks when taxonomy client-behaviour cases and provisional prohibitions are grouped — under the ~25-task ceiling (delivery plan §6.3 / skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — first AI
      surface is additive; non-enrolled clinics see no AI chrome; no hospital-scale or
      always-online assumption (§4.1; A11; spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — one Flutter feature module family and one
      clinic settings key + read RPC; no new deployable.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — Feature
      Surfaces and host in `frontend/`; availability flag in `backend/`; `ai-platform/` unchanged.
      Gateway remains the additive, non-primary §14 component (no domain logic, no business
      data, no write path into Supabase); this slice does not add or change Worker code, so the
      §14 acknowledgement is recorded as inherited boundary. Flutter still holds no prompts,
      providers, or AI business rules (§4.1; §14; spec Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — availability flag is an
      additive `ai_internal` settings key read through SECURITY DEFINER public wrapper; surface
      performs no clinical writes; `advisory_display` accept does not invoke F2.
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — availability RPC granted to `authenticated` only;
      context still via E3 under caller RLS; soft-delete and clinic audit unchanged; no AI
      request state in clinic DB (§4.2 Boundary note).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — explicit
      accept/discard; no auto-commit; non-enrolled / unreachable / quota / unavailable are
      first-class UI states that never block clinical workflows (A11; FR-010–FR-011).

## Project Structure

### Documentation (this feature)

```text
specs/038-first-ai-feature-surface/
├── plan.md                              # This file
├── spec.md                              # /ai-platform-specify + /ai-platform-clarify (authoritative)
├── contracts/
│   └── ai-availability-flag.md          # Frozen: enrolled + platform_base_url store/read shape
└── quickstart.md                        # Written during the implement-phase Documentation task
```

`data-model.md` is **not** produced — E4 defines no D1 entities (spec Key Entities: "Not applicable"). The availability flag is clinic-side configuration; its wire shape lives in `contracts/ai-availability-flag.md`.

`research.md` is **not** produced — the research is `docs/architecture/17-ai-platform.md`.

`contracts/` is produced because one **Freezes** entry has a wire shape later slices’ **Consumes** must bind to: the AI availability flag clinic-side store (`enrolled` + `platform_base_url`). The other Freezes (Feature Surfaces UI rules, provisional-content client rules, terminal-payload authority, request-reference display, degraded mode) are behavioural and bind to the Flutter modules under `frontend/lib/features/ai/`, not to additional prose contract files (same posture as E2 behavioural Freezes).

`quickstart.md` (written during the implement-phase Documentation task, per `.specify/templates/ai-platform-quickstart-template.md`) will contain:

- **§1 Architecture context** — E4 row of the delivery plan (§3.6) and §4.1 / §6.4 / §13.2 / §4.2 / §5.4 / A11; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — first AI Feature Surface (`prose` / `advisory_display`); degraded-mode states; AI availability flag + read RPC; standalone host for tests/CP3.
- **§3 Files to review** — this slice’s `frontend/lib/features/ai/`, `frontend/test/widget/ai/`, the availability migration, and `contracts/ai-availability-flag.md` only.
- **§5 Run the automated suite** — slice-only `flutter test` against this slice’s widget test files; no full-suite `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — open the surface widget, degraded states, availability contract, and a focused widget test; confirm E1 guard still covers `frontend/lib/features/ai/`.
- **§7 Manual validation** — optional: open the standalone AI host route when enrolled (CP3 entry with D4); confirm provisional draft styling and degraded states visually. Omit detailed deploy steps — widget suite is the primary verification path (DP-3).

### Source Code (repository root)

```text
frontend/
├── lib/
│   ├── app/
│   │   ├── app_routes.dart                    # MODIFIED — add standalone AI host route constant
│   │   └── router.dart                        # MODIFIED — register host route (Clarification Q2)
│   ├── core/
│   │   └── ai/                                # UNCHANGED — Consumes E2 + E3
│   │       ├── ai_client_sdk.dart
│   │       ├── ports.dart
│   │       ├── taxonomy.dart
│   │       ├── sse_events.dart
│   │       ├── context_resolver.dart
│   │       ├── context_registration.dart
│   │       └── context_provider_port.dart
│   └── features/
│       └── ai/                                # NEW — Clarification Q1
│           ├── availability/
│           │   ├── ai_availability.dart       # NEW — {enrolled, platformBaseUrl} model + port
│           │   └── ai_availability_reader.dart# NEW — clinic RPC / injectable reader (FR-008/009)
│           ├── degraded/
│           │   ├── ai_degraded_mode.dart      # NEW — distinct states (A11; FR-010–013)
│           │   └── ai_degraded_view.dart      # NEW — first-class UI (not error dialogs)
│           ├── surface/
│           │   ├── first_ai_feature_surface.dart  # NEW — prose surface, accept/discard, refs
│           │   ├── provisional_prose_view.dart    # NEW — draft Key/Semantics + AI tokens (T1)
│           │   └── request_reference_view.dart    # NEW — failure reference display (§13.2)
│           └── host/
│               └── ai_feature_host_page.dart  # NEW — standalone host for tests + CP3 (Q2)
├── test/
│   └── widget/
│       └── ai/                                # NEW — Flutter widget (spy) suite T1–T21
│           ├── ai_surface_test_harness.dart   # NEW — spies: SDK, Resolver, availability, net
│           ├── first_ai_feature_surface_test.dart  # NEW — T1–T7, T13–T17, T20 (surface)
│           └── ai_degraded_mode_test.dart     # NEW — T8–T12, T18–T19, T21 (degraded/flag)
└── tool/
    └── architecture_guard/                    # UNCHANGED — Consumes E1 / R-12 (FR-015; T20)

backend/
├── supabase/
│   └── migrations/
│       └── 20260802140000_ai_availability_flag.sql  # NEW — settings key + get_ai_availability
└── tests/
    └── run_ai_platform_trust_tests.sh         # UNCHANGED this slice (named tests are Flutter)

# ai-platform/ — UNCHANGED (Consumes streaming/taxonomy via E2 SDK only; no rewrite)
```

**Structure Decision**: Feature Surfaces live under `frontend/lib/features/ai/` and import the SDK/Resolver from `core/ai` (Clarification Q1). A standalone host page/route under `features/ai/host/` is the test + CP3 entry; this slice does not embed the surface in a production clinical screen (Clarification Q2). Provisional draft distinctness uses a stable test `Key` / Semantics marker plus existing AI draft styling tokens (`surfaceAi` / `textAi` / `borderAi`) asserted by T1 (Clarification Q3). Availability storage reuses B1 `ai_internal.app_settings` rather than inventing a parallel table (see contract). Widget tests mirror the repo’s `frontend/test/widget/<feature>/` layout with an injectable harness.

## Consumes Binding

E4 has `Needs: E2, E3` (delivery plan §3.6). It also Consumes **A2 / A6 via E2** (error taxonomy and request reference) and **§6.4 streaming contract via the SDK**. Changing any is out of scope (delivery plan §2.3).

| Consumes entry | Existing module / file / type it binds to |
| --- | --- |
| **E2 — AI Client SDK** (§4.1 AI Client SDK; §5.5; §5.4) | `frontend/lib/core/ai/ai_client_sdk.dart` (`AiClientSdk`, `AiInvokeSession`, `lastRequestReference`), `ports.dart` (`CapabilityInvokeInput`, `HttpsSubmitPort`, `SseConnection`, `PlatformHttpException`, `TransportFailure`), `sse_events.dart` (`AcceptedEvent`, `ContentChunkEvent`, `HeartbeatEvent`, `CompletedEvent` / `FailedEvent` / `CancelledEvent`, `TerminalState`), `taxonomy.dart` (`TaxonomyCode`, wire maps). E4 renders and degrades on top of submit / SSE / cancel / last-reference retention; it does not reinterpret transport, idempotency, SSE framing, remint, or terminal no-retry rules, and does not modify these modules. |
| **E3 — Context Resolver registry, first context RPC, and client contract test** (§4.1 Context Resolver; §5.2; §4.2 Context provider RPCs; §13.5) | `frontend/lib/core/ai/context_resolver.dart` (`ContextResolver`, `ContextResolveSuccess` / `ContextResolveFailure`), `context_registration.dart` (`contextRegistration`, `visitChiefComplaintV1Key`), `context_provider_port.dart`, frozen artifacts `specs/037-context-resolver-registry/contracts/context-resolver.md` and `context-provider-rpc.md`. E4 obtains context through the registry for the first surface; it does not branch the Resolver on capability id, add per-feature glue resolvers outside the registry, rewrite the contract test, or modify these modules. |
| **A2 / A6 via E2 — Error taxonomy and request reference** (§5.4; §13.2) | Dart taxonomy mirror `frontend/lib/core/ai/taxonomy.dart` and failure/terminal types carrying `requestReference` (`FailedEvent` / `FailedTerminal` / `PlatformHttpException`); platform source of truth remains `ai-platform/src/errors.ts` / A6 framing (unchanged). E4 displays references and applies named §5.4 Client behaviours; it adds no taxonomy codes and changes none. |
| **§6.4 streaming contract via the SDK / prior band D surfaces** | Client event kinds and one-terminal-event rule as consumed through E2 `sse_events.dart` / `AiInvokeSession` (`accepted`, content/heartbeat, exactly one of `completed` / `failed` / `cancelled`). E4 does not redefine stream event kinds or the one-terminal-event rule. |

No Consumes entry lacks an existing implementation. None is modified (delivery plan §2.3). Stop condition 2 is not triggered.

## Components Touched

Two §4 components, with explicit reason:

1. **§4.1 AI Feature Surfaces** — per-feature UI for draft rendering, provisional/draft styling, explicit accept/discard, degraded-mode states, and request-reference display on failure (§4.1 table; delivery plan §3.6 Done when).
2. **§4.2 AI availability flag** — clinic-side store of enrolled status and platform base URL so the client can hide affordances without probing the AI platform (§4.2; Open Decision 8; Done when).

**Reason for two components:** Delivery plan §3.6 row E4 Done when and this slice’s Freezes jointly require (a) the Flutter Feature Surface + degraded UX and (b) the clinic-side AI availability flag. Architecture places surfaces on the client (§4.1) and the enrollment/base-URL fact on Supabase (§4.2). Touching both is the minimal way to freeze what E4’s Canonical cell names; it is not scope creep into E2/E3/F2/H3 or gateway stages.

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.1 AI Feature Surfaces | **Created** | This slice’s Flutter deliverable (§4.1; delivery plan §3.6). |
| §4.1 AI Client SDK | **Not touched** | Consumes E2 only |
| §4.1 Context Resolver | **Not touched** | Consumes E3 only |
| §4.1 Conversation store | **Not touched** | H band |
| §4.2 AI availability flag | **Created** | Enrolled + platform base URL store/read (§4.2; Done when) |
| §4.2 Installation keystore / AI token issuer / context provider / acceptance | **Not touched** | B1 / E3 / F2 |
| §4.3.* gateway stages | **Not touched** | Out of scope; Consumes streaming/taxonomy via E2 only |

Stop condition 5 (multi-component without reason) is not triggered — reason recorded above. Task count stays under ~25.

## Files

| File | FR(s) | Status |
| --- | --- | --- |
| `specs/038-first-ai-feature-surface/contracts/ai-availability-flag.md` | Freezes — availability flag; FR-008, FR-009, FR-012 | NEW — frozen store/read shape for later Consumes. |
| `backend/supabase/migrations/20260802140000_ai_availability_flag.sql` | FR-008, FR-009 | NEW — seed `ai.availability` on `ai_internal.app_settings`; `auth_internal` + `public.get_ai_availability()` returning `{ enrolled, platform_base_url }`; default non-enrolled. |
| `frontend/lib/features/ai/availability/ai_availability.dart` | FR-008, FR-009, FR-012 | NEW — model + injectable port for clinic-side availability read (test doubles for T8/T10/T21). |
| `frontend/lib/features/ai/availability/ai_availability_reader.dart` | FR-008, FR-009, FR-012; T21 | NEW — production reader of `get_ai_availability`; never probes the AI platform to discover enrollment. |
| `frontend/lib/features/ai/degraded/ai_degraded_mode.dart` | FR-010, FR-011, FR-013; T8–T12, T18–T19 | NEW — distinct first-class states: non-enrolled, unreachable/offline, quota exhausted, AI unavailable, installation suspended, forbidden capability; maps §5.4 Client behaviours. |
| `frontend/lib/features/ai/degraded/ai_degraded_view.dart` | FR-010, FR-011; T9, T11–T12 | NEW — normal-state UI for degraded modes (unreachable is not an error dialog); does not block clinical workflows. |
| `frontend/lib/features/ai/surface/provisional_prose_view.dart` | FR-001, FR-003, FR-005; T1 | NEW — live provisional prose with draft Key/Semantics + `surfaceAi`/`textAi`/`borderAi` tokens (Clarification Q3). |
| `frontend/lib/features/ai/surface/request_reference_view.dart` | FR-006, FR-007; T5, T13–T14 | NEW — displays request reference on failure; uses SDK-retained last reference so reporting after screen close remains possible (§13.2; Consumes E2). |
| `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` | FR-001–FR-007, FR-013–FR-016; T1–T7, T15–T17, T20 | NEW — first capability surface (`clinic.visit_summary`, `prose`, `advisory_display`): resolve context via E3, invoke via E2, render provisional, enable accept/discard only after `completed`, use terminal payload (not chunk assembly), never persist/export provisional, apply taxonomy client behaviours. |
| `frontend/lib/features/ai/host/ai_feature_host_page.dart` | FR-001, FR-009, FR-012; Clarification Q2 | NEW — standalone host composing availability gate + surface for widget tests and CP3 entry. |
| `frontend/lib/app/app_routes.dart` | FR-001; Clarification Q2 | MODIFIED — add standalone AI host route constant. |
| `frontend/lib/app/router.dart` | FR-001; Clarification Q2 | MODIFIED — register host route that builds `AiFeatureHostPage` from GoRouter `extra` dependencies (CP3 composition; not embedded in a clinical screen). |
| `frontend/test/widget/ai/ai_surface_test_harness.dart` | FR-001–FR-016 (test support) | NEW — spies/fakes for SDK streams, Resolver, availability flag, reachability/network, persistence/export probes. |
| `frontend/test/widget/ai/first_ai_feature_surface_test.dart` | FR-001–FR-007, FR-014–FR-016; T1–T7, T13–T17, T20 | NEW — surface widget suite. |
| `frontend/test/widget/ai/ai_degraded_mode_test.dart` | FR-008–FR-013; T8–T12, T18–T19, T21 | NEW — degraded-mode + availability-flag widget suite. |
| `specs/038-first-ai-feature-surface/quickstart.md` | — | NEW — written during the implement-phase Documentation task (sections named above). |

Every file traces to an `FR-###` (or Freezes / deferred Documentation). No file is created for an unstated requirement. No Consumes module is rewritten. No `ai-platform/` file is touched.

## Test Layout

The spec’s Test plan names twenty-one tests at layer **Flutter widget (spy)** (delivery plan §3.11.5 row E4). That is the client Flutter widget suite (DP-3). §13.5’s Architecture guard covers T20 (R-12); Client contract tests remain E3’s and are not re-owned here. Tests join CI permanently (delivery plan §3.10). All cases live under `frontend/test/widget/ai/` and run with injectable spies — no live Worker/provider required (spec Assumptions).

| # | Named test | Spec layer | Where it lives | Asserts |
| --- | --- | --- | --- | --- |
| T1 | `surface_provisional_content_visually_distinct` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | Live/provisional prose marked draft via Key/Semantics + AI draft tokens (Clarification Q3; §6.4; §4.1) |
| T2 | `surface_no_commit_control_before_completed` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | No commit/save/accept control before terminal `completed` |
| T3 | `surface_accept_after_completed_behaves` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | Accept acknowledges validated terminal payload; no F2 clinical write (`advisory_display`) |
| T4 | `surface_discard_behaves` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | Discard clears surface content; writes nothing clinical |
| T5 | `surface_failure_displays_request_reference` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | Failure UI displays the request reference (§13.2; §5.4) |
| T6 | `surface_provisional_does_not_survive_rebuild` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | Provisional content does not survive widget rebuild (§6.4 inv. 2) |
| T7 | `surface_provisional_does_not_survive_restart` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | Provisional content does not survive app-restart simulation (§6.4 inv. 2) |
| T8 | `degraded_non_enrolled_hides_affordances_no_network` | Flutter widget (spy) | `ai_degraded_mode_test.dart` | Non-enrolled: no AI affordances; spy shows zero AI-platform network calls |
| T9 | `degraded_unreachable_is_normal_state_not_error_dialog` | Flutter widget (spy) | `ai_degraded_mode_test.dart` | Unreachable → normal state, not error dialog; clinical work not blocked (A11) |
| T10 | `degraded_enrolled_reachable_shows_affordances` | Flutter widget (spy) | `ai_degraded_mode_test.dart` | Enrolled and reachable shows AI affordances |
| T11 | `degraded_quota_exhausted_distinct_state` | Flutter widget (spy) | `ai_degraded_mode_test.dart` | `quota_exhausted` → distinct first-class quota UI (§5.4; A11) |
| T12 | `degraded_ai_unavailable_distinct_from_offline_and_quota` | Flutter widget (spy) | `ai_degraded_mode_test.dart` | AI-unavailable distinct from offline and from quota (A11) |
| T13 | `surface_internal_error_shows_request_reference` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | `internal_error` failure displays request reference |
| T14 | `surface_context_invalid_shows_request_reference` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | `context_invalid` failure displays request reference |
| T15 | `surface_uses_terminal_payload_not_chunk_assembly` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | Final answer equals terminal validated payload, not delta assembly (§6.4 inv. 1) |
| T16 | `surface_provisional_never_exported` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | No export path emits provisional (pre-`completed`) content |
| T17 | `surface_provisional_never_persisted` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` | Persistence probe: provisional not written to durable storage |
| T18 | `surface_installation_suspended_hides_ai_features` | Flutter widget (spy) | `ai_degraded_mode_test.dart` | `installation_suspended` → hide AI features (§5.4); clinical usable |
| T19 | `surface_forbidden_capability_hides_affordance` | Flutter widget (spy) | `ai_degraded_mode_test.dart` | `forbidden_capability` → hide affordance for this role (§5.4) |
| T20 | `surface_contains_no_prompt_provider_or_model_identifiers` | Flutter widget (spy) | `first_ai_feature_surface_test.dart` (+ E1 guard on `features/ai/`) | Feature surface sources pass E1 architecture guard (R-12) |
| T21 | `availability_flag_readable_without_platform_probe` | Flutter widget (spy) | `ai_degraded_mode_test.dart` | Enrollment + base URL read from clinic flag; non-enrolled path makes no platform probe |

Every named test places in the Flutter widget (spy) layer — stop condition 3 not triggered. Coverage matches delivery plan §3.10 / spec Coverage paragraph (happy paths, failure/reference branches, every degraded-mode branch, provisional prohibitions, terminal-payload authority, R-12, no commit before `completed`, no network when non-enrolled, unreachable not an error dialog).

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2). Within this slice:

1. **Frozen availability contract** — write/confirm `contracts/ai-availability-flag.md` so later Consumes bind to an artifact (delivery plan DP-4 / Freezes).
2. **Clinic availability flag (FR-008)** — land migration seeding `ai.availability` and `get_ai_availability()`; land Dart model + injectable reader.
3. **Harness + degraded-mode model (FR-009–FR-013; T8–T12, T18–T19, T21)** — land `ai_surface_test_harness.dart`, `ai_degraded_mode.dart` / view; prove non-enrolled no-network, enrolled+reachable, unreachable-as-normal-state, quota vs offline vs unavailable, suspended/forbidden behaviours alongside.
4. **Provisional prose view (FR-001, FR-003; T1–T2)** — land draft Key/Semantics + AI tokens; prove visual distinctness and no commit control before `completed` (Clarification Q3).
5. **Surface invoke path (FR-003–FR-007, FR-014–FR-016; T3–T7, T13–T17, T15)** — land `first_ai_feature_surface.dart` wiring E3 resolve + E2 invoke; prove accept/discard, terminal-payload authority, failure references, provisional rebuild/restart/export/persist prohibitions.
6. **Standalone host + route (Clarification Q2; FR-001)** — land `ai_feature_host_page.dart` and register route for tests/CP3 entry (not clinical embed).
7. **R-12 guard (FR-015; T20)** — prove `features/ai/` sources pass E1 architecture guard.
8. **Documentation** — fill `quickstart.md` after implementation and verification (sections named above).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations. Table omitted.
