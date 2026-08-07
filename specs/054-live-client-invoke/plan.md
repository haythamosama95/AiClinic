# Implementation Plan: Live client invoke on the first AI feature surface (I3)

**Branch**: `ai/054-i3-live-client-invoke` | **Date**: 2026-08-07 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/054-live-client-invoke/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

I3 composes the Flutter `/ai` visit-summary (or equivalent) host onto the live Worker path: production AAT mint and HTTPS submit adapters from E2, required context keys through E3 (optionally driven by I2 discovery), SSE consume-to-terminal with provisional `prose` rendering and no commit affordance until `completed`, request-reference display on failure, and A11 degraded states (non-enrolled / unreachable) unchanged. It sits in Band I after E2, E3, E4, I1, and I2 (`Needs: E2, E3, E4, I1, I2`); with I1 it reifies CP3 on the live composed host (`03-ai-platform-delivery-plan.md` §3.10 / §5 CP3).

## Technical Context

**Language/Version**: Dart (SDK `^3.11.5` as declared in `frontend/pubspec.yaml`) for production port adapters, discovery client, hub composition, and Flutter widget/integration suite.

**Primary Dependencies**: Flutter desktop client under `frontend/`; E2 AI Client SDK under `frontend/lib/core/ai/` (`AiClientSdk`, `AatMintPort`, `HttpsSubmitPort`, `sse_events`, `taxonomy` — Consumes, not modified); E3 Context Resolver siblings (`ContextResolver`, `SupabaseContextProviderPort`, `context_registration` — Consumes, not modified); E4 first surface / host / degraded / availability under `frontend/lib/features/ai/` (Consumes, composition only — replace unconfigured mint/submit stubs); I1 live `POST /v1/requests` on the Worker (client of that path — does not rewrite `worker.ts` / pipeline); I2 frozen discovery HTTP wire (`specs/053-discovery-http-config-readers/contracts/discovery-http.md` — Bearer AAT, etag/`If-None-Match`, auth-failure taxonomy mapping). Clinic mint RPC `public.issue_ai_token` (Band B). Existing `http` package (`^1.4.0`) for HTTPS submit and discovery. First capability remains Open Decision 1 / E4: `clinic.visit_summary` / `prose` / `advisory_display`. No Worker source changes, no Supabase schema/RPC changes, no new pub packages, no I4 entitle-and-grant or `context_required` self-heal.

**Storage**: N/A — no D1 entities; no new clinic tables. Ephemeral client state only (provisional prose never persisted — Consumes E4 / §6.4).

**Testing**: Flutter widget + integration (delivery plan §3.12.9 row I3; §13.5 client / widget coverage + Architecture guard for T11). Named cases T1–T11 via `flutter test` against spies/fakes for mint, submit, discovery, network, and ports — live Worker inference not required for the suite (spec Assumptions; DP-3). Suite joins CI permanently (§3.11).

**Target Platform**: Flutter Windows desktop client (`frontend/`). Consumes the already-deployed `ai-platform/` Worker submit (I1) and discovery (I2) paths over HTTPS; this slice does not change Worker code.

**Project Type**: Flutter client composition slice under `frontend/` — Band I live wiring of already-frozen §4.1 modules onto I1/I2 wires. Not a Worker slice (`ai-platform/` unchanged). Gateway remains additive, non-primary (§14).

**Performance Goals**: None beyond ordinary client UI. I3 adds no Quota DO round trip, no D1 insert, and no R2 object on the Worker path; platform I/O budgets (§6.1, §7.5, §13.6; delivery plan §6.4) remain those already frozen by I1/I2. Client may call `GET /v1/capabilities` and `POST /v1/requests` once per user action as the existing §5.5 surfaces prescribe — no second DO/R2 invented here.

**Constraints**:
- Compose production AAT mint + HTTPS submit into the hub defaults; spy proves ports are not unconfigured stubs or test fakes (FR-001, FR-010; T8).
- Resolve required context keys through E3 generic key-list API — no capability-id branching (FR-002).
- Stable client-generated idempotency key across transport retries of one user action (FR-003; Consumes E2; T9).
- SSE to exactly one terminal; provisional draft while in flight; no commit affordance before `completed`; terminal payload authoritative — never chunk assembly (FR-004–FR-006; §6.4; T2–T3, T5).
- Every failure presentation shows request reference; branch on §5.4 taxonomy codes (FR-007, FR-011; T4).
- Non-enrolled: hide affordances, zero Worker/platform probes (FR-008; T6). Unreachable: normal banner, not error dialog (FR-009; T7).
- When discovery is consumed: I2 wire only (Bearer AAT, etag revalidation); no reimplementation of filtering; auth failure → taxonomy body, no manifests payload; may surface `installation_suspended` (FR-012; T10).
- No prompt/provider/model identifiers; pass E1 architecture guard (FR-013; T11; R-12).
- First capability remains non-clinical-record `prose` / `advisory_display` (FR-014; Open Decision 1).
- Do not modify Consumes modules (E2/E3/E4/I1/I2 contracts) — delivery plan §2.3.
- Out of scope: I4 entitle-and-grant, J2/`context_required` self-heal, F2 clinical accept write, Band G, H-band chat.

**Scale/Scope**: One §4 component group (§4.1 Client-side components — composition of SDK + Resolver + Feature Surfaces onto live I1/I2 wires; see Components Touched). Roughly: two production port adapters, one discovery client, hub composition wiring, one widget/integration test file for T1–T11, one quickstart. Fourteen FRs. Eleven named tests. Roughly 16–22 tasks — under the ~25-task ceiling (delivery plan §6.3 / plan stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — live invoke
      remains additive; non-enrolled and unreachable installations continue clinical work without
      AI (A11; constitution I; spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — Flutter composition of existing ports onto
      existing Worker HTTP surfaces; no new deployable.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — I3 lives
      in `frontend/` (hub + production adapters + discovery client). It consumes `ai-platform/`
      submit (I1) and discovery (I2) without rewriting them. **§14 acknowledgement:** the Worker
      is an additive, non-primary component with no domain logic, no business data, and no write
      path into Supabase; Flutter still holds no prompts, providers, or AI business rules
      (§4.1; §14; spec Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — context resolution stays
      under caller RLS via E3; AAT mint stays on clinic `public.issue_ai_token`; I3 performs no
      clinical writes and does not weaken token/tenant isolation (spec Data Integrity & Security).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — live calls use Bearer AAT; discovery/submit auth
      failures map to §5.4 taxonomy; soft-delete and clinic audit unchanged.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — provisional content
      never enters clinical records until a later acceptance path; non-enrolled / unreachable
      remain first-class states that never block clinical workflows (A11; FR-008–FR-009; Open
      Decision 1 `advisory_display`).

## Project Structure

### Documentation (this feature)

```text
specs/054-live-client-invoke/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify (authoritative; SUCCESS_NO_QUESTIONS)
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — spec `### Key Entities` is "Not applicable" (no D1 entities or new contract types).

`research.md` is **never** produced on this platform — the research is
`docs/architecture/ai-platform/01-ai-platform.md`.

`contracts/` is **not** produced — Band I freezes no new contract (Delivery Plan §3.10; §2.3; spec
**Freezes**: None). Later slices bind to the composed Flutter modules and to already-frozen artifacts
(E2 ports/SDK, E3 resolver, E4 surface, I2 `discovery-http.md`), not to a new I3 wire file.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:
- **§1 Architecture context** — I3 row of the delivery plan (§3.10) and §4.1 / §5.5 / §5.4 / §6.4 /
  A11; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — production AAT mint + HTTPS submit adapters; discovery client
  binding to I2; hub composition replacing unconfigured stubs; live invoke on the first surface.
- **§3 Files to review** — only this slice's `frontend/lib/core/ai/` production adapters /
  discovery client, hub composition under `frontend/lib/features/ai/`, and this slice's widget
  test file(s).
- **§5 Run the automated suite** — slice-only `flutter test` against this slice's live-invoke
  widget/integration test file(s) (T1–T11); no full-suite `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — open hub composition, production mint/submit ports, discovery
  client; confirm spy on production ports; confirm E1 guard covers composition sources.
- **§7 Manual validation** — optional: enrolled desktop `/ai` host against a local Worker for a
  live stream (this slice exposes live client behaviour beyond CI); omit when widget suite alone
  proves Done when for CP3 review.

### Source Code (repository root)

```text
frontend/
├── lib/
│   ├── core/
│   │   └── ai/
│   │       ├── ai_client_sdk.dart                 # UNCHANGED (Consumes E2)
│   │       ├── ports.dart                         # UNCHANGED (Consumes E2 — AatMintPort / HttpsSubmitPort)
│   │       ├── sse_events.dart                    # UNCHANGED (Consumes E2)
│   │       ├── taxonomy.dart                      # UNCHANGED (Consumes E2)
│   │       ├── context_resolver.dart              # UNCHANGED (Consumes E3)
│   │       ├── context_registration.dart          # UNCHANGED (Consumes E3)
│   │       ├── context_provider_port.dart          # UNCHANGED (Consumes E3)
│   │       ├── supabase_context_provider_port.dart# UNCHANGED (Consumes E3)
│   │       ├── supabase_aat_mint_port.dart        # NEW — production AatMintPort → public.issue_ai_token
│   │       ├── https_submit_port.dart             # NEW — production HttpsSubmitPort → POST /v1/requests + SSE
│   │       └── discovery_client.dart              # NEW — GET /v1/capabilities client (Consumes I2 wire)
│   └── features/
│       └── ai/
│           ├── presentation/pages/ai_page.dart    # MODIFIED — compose production mint/submit; enable live invoke
│           ├── host/ai_feature_host_page.dart     # UNCHANGED unless a minimal composition hook is required
│           │                                      # without rewriting E4 contracts (prefer composer in ai_page)
│           ├── surface/                           # UNCHANGED (Consumes E4)
│           ├── degraded/                          # UNCHANGED (Consumes E4)
│           └── availability/                      # UNCHANGED (Consumes E4)
├── test/
│   └── widget/
│       └── ai/
│           └── live_client_invoke_test.dart       # NEW — T1–T11 Flutter widget + integration
└── tool/
    └── architecture_guard/                        # UNCHANGED — T11 invokes existing E1 guard on composition paths

ai-platform/                                       # UNCHANGED (Consumes I1 + I2 live HTTP — client only)
```

**Structure Decision**: Production adapters and the discovery client live beside E2/E3 under
`frontend/lib/core/ai/` (same pattern as `SupabaseContextProviderPort`) so Feature Surfaces continue
to import transport from `core/ai` without gaining prompt/provider knowledge. Hub composition
replaces `_UnconfiguredAatMintPort` / `_UnconfiguredHttpsSubmitPort` and `autoInvoke: false` on
`_LiveVisitSummaryHost` in `ai_page.dart` — the Done-when / T8 spy target. Required context keys from
discovery are resolved in that composer and passed into existing `AiFeatureHostDependencies.requiredContextKeys`
(E4 already documents that hosts SHOULD supply discovery keys). Consumed E2/E3/E4 modules and the
Worker remain unmodified (delivery plan §2.3).

## Consumes Binding

| Consumes entry | Existing module / file / type it binds to | How I3 binds to it |
| --- | --- | --- |
| **E2 — AI Client SDK** (AAT acquire/cache, submit with stable idempotency key, SSE to one terminal, cancel by close, last request-reference, transport-only retries, single `unauthenticated` remint) | `frontend/lib/core/ai/ai_client_sdk.dart` (`AiClientSdk`, `AiInvokeSession`, `lastRequestReference`); `ports.dart` (`AatMintPort`, `HttpsSubmitPort`, `CapabilityInvokeInput`, `SubmitRequestHeaders`, `SseConnection`, `PlatformHttpException`); `sse_events.dart`; `taxonomy.dart`. Spec/plan: `specs/036-ai-client-sdk/`. | I3 **implements** production `AatMintPort` / `HttpsSubmitPort` and injects them into `AiClientSdk`. It does **not** reinterpret transport, idempotency, SSE framing, or remint rules, and does **not** modify SDK sources. |
| **E3 — Context Resolver registry** (generic key-list resolution under caller RLS, screen-scoped cache) | `frontend/lib/core/ai/context_resolver.dart` (`ContextResolver`); `context_registration.dart`; `context_provider_port.dart`; `supabase_context_provider_port.dart`. Spec/plan: `specs/037-context-resolver-registry/`. Contracts: `context-resolver.md`, `context-provider-rpc.md`. | Live host / surface continues to call `resolver.resolve(requiredContextKeys)`. I3 may supply the key list from discovery; it does **not** branch the Resolver on capability id or add per-feature glue resolvers outside the registry. |
| **E4 — First AI feature surface and degraded mode** (provisional/draft, no commit until `completed`, request-reference on failure, availability gate, degraded states) | `frontend/lib/features/ai/surface/first_ai_feature_surface.dart` (`clinic.visit_summary` / `prose` / `advisory_display`); `provisional_prose_view.dart`; `request_reference_view.dart`; `host/ai_feature_host_page.dart` (`AiFeatureHostDependencies`); `degraded/*`; `availability/*`. Spec/plan: `specs/038-first-ai-feature-surface/`. | I3 replaces the hub's unconfigured mint/submit stubs with production adapters and enables live invoke. It does **not** redefine surface UX, provisional rules, or degraded-mode states. |
| **I1 — Worker request orchestrator** (`POST /v1/requests`; live `preAccept` + `eventSource`) | `ai-platform/src/worker.ts` (production `preAccept` / `eventSource` composition); `ai-platform/src/adapter.ts` (deferred `accepted`; taxonomy HTTP on pre-accept failure). Spec/plan: `specs/052-worker-request-orchestrator/`. | Production `HttpsSubmitPort` is an HTTPS **client** of that live path. I3 does **not** rewrite Worker orchestration, pipeline modules, or A6 framing. |
| **I2 — Discovery HTTP and production config readers** (`GET /v1/capabilities`) | Frozen artifact `specs/053-discovery-http-config-readers/contracts/discovery-http.md`; live handler `ai-platform/src/discovery/index.ts` (via Worker route). | Flutter discovery client uses Bearer AAT, honors etag/`If-None-Match`, maps auth failure to taxonomy (no manifests body; may forward `installation_suspended`). I3 does **not** reimplement discovery filtering, etag computation, or grant/lifecycle overlay (those remain C1 via I2). |

No consumed entry lacks an implementation. No consumed **contract** is rewritten (delivery plan §2.3). New production adapters and the discovery client are I3 composition surfaces that **implement** E2 ports / **call** I2's frozen wire — they are not changes to Consumes.

## Components Touched

| §4 component | What I3 changes | Behaviour added? |
| --- | --- | --- |
| §4.1 Client-side components (AI Client SDK + Context Resolver + AI Feature Surfaces) | **Composition only** — production `AatMintPort` / `HttpsSubmitPort` implementations; discovery client for required keys; hub wiring that injects those ports into the existing E4 host/surface and enables live invoke. Does not change SDK transport rules, Resolver registry API, or E4 UX/degraded contracts. | Yes — the first surface runs a live invoke against I1/I2 wires instead of idle unconfigured stubs (Delivery Plan §3.10 Done when; CP3 client half). |

**Written reason (single §4 component group):** Delivery plan §3.10 row **I3** Canonical is `§4.1, §5.5, §5.4, §6.4, A11` and Done when requires composing E2 + E3 onto E4 against live I1/I2. Band I adds no new §4 component (DP-8 / §3.10); §5.5 / §5.4 / §6.4 / A11 are contracts and amendments consumed by that composition, not separate §4 component groups. Touching only the §4.1 client group matches the slice row.

`ai-platform/` Worker modules are **not** touched (Consumes I1/I2 as HTTP clients only).

## Files

| File | Created / Modified | Traces to |
| --- | --- | --- |
| `frontend/lib/core/ai/supabase_aat_mint_port.dart` | Created | FR-001, FR-010 — production `AatMintPort` calling clinic `public.issue_ai_token` (Band B issuer path consumed by E2). |
| `frontend/lib/core/ai/https_submit_port.dart` | Created | FR-001, FR-003, FR-004, FR-010 — production `HttpsSubmitPort`: HTTPS `POST /v1/requests` with A6 headers (`Authorization` Bearer AAT, `x-idempotency-key`, `x-trace-id`, `x-capability-version`), open SSE `SseConnection`, map pre-stream taxonomy HTTP to `PlatformHttpException`. |
| `frontend/lib/core/ai/discovery_client.dart` | Created | FR-002, FR-012 — `GET /v1/capabilities` client per I2 `discovery-http.md` (Bearer AAT, etag/`If-None-Match`); extract required context keys for the first capability; auth failure → taxonomy error, no manifests body (incl. `installation_suspended`). |
| `frontend/lib/features/ai/presentation/pages/ai_page.dart` | Modified | FR-001, FR-002, FR-008, FR-009, FR-010, FR-014 — compose production mint/submit into `_LiveVisitSummaryHost` `AiClientSdk`; supply discovery-derived (or default) required keys; enable live invoke (`autoInvoke: true` when enrolled/reachable composition applies); remove unconfigured stubs as hub defaults. |
| `frontend/test/widget/ai/live_client_invoke_test.dart` | Created | SC-001..SC-007 — named tests T1–T11 (Flutter widget + integration / spy / architecture guard). |
| `specs/054-live-client-invoke/quickstart.md` | Created (implement phase) | — template-mandated review surface; sections named above. |

Every code file traces to an `FR-###`. No file is created for an unstated requirement. Consumed modules under `core/ai/` (SDK, Resolver) and `features/ai/` (surface/host/degraded/availability) stay unchanged aside from hub composition in `ai_page.dart`. Worker tree unchanged.

Optional minimal touch to `ai_feature_host_page.dart` is **out of the default plan** — prefer passing composed deps from `ai_page.dart`. If implement discovers an unavoidable host hook that does not rewrite E4 contracts, it must still trace to FR-001/FR-002/FR-010 and must not expand Consumes.

## Test Layout

The spec's `### Test plan` names eleven Flutter widget + integration tests (delivery plan §3.12.9 I3;
§13.5 client widget coverage; Architecture guard for T11). All live under
`frontend/test/widget/ai/live_client_invoke_test.dart` (one file — same surface under test; spies for
ports/network/discovery). Reuse E4 harness patterns (`ai_surface_test_harness.dart` / fakes) where
they do not leave test fakes as hub defaults under test for T8.

| Spec Test plan name | Test id | File | §13.5 layer | Asserts (FR / SC) |
| --- | --- | --- | --- | --- |
| `live_host_mints_aat_resolves_context_submits_https` | T1 | `live_client_invoke_test.dart` | Flutter widget + integration | FR-001, FR-002, FR-003 / SC-001 — enrolled + reachable: mint AAT, resolve keys via E3, HTTPS submit with stable idempotency key |
| `live_host_consumes_sse_to_terminal_renders_provisional` | T2 | `live_client_invoke_test.dart` | Flutter widget + integration | FR-004, FR-005 / SC-001 — SSE to terminal; provisional draft while in flight |
| `live_host_no_commit_control_before_completed` | T3 | `live_client_invoke_test.dart` | Flutter widget + integration | FR-005 / SC-002 — no commit/save/accept before `completed` |
| `live_host_failure_displays_request_reference` | T4 | `live_client_invoke_test.dart` | Flutter widget + integration | FR-007, FR-011 / SC-003 — failure shows request reference |
| `live_host_uses_terminal_payload_not_chunk_assembly` | T5 | `live_client_invoke_test.dart` | Flutter widget + integration | FR-006 / SC-002 — final answer = validated terminal payload |
| `degraded_non_enrolled_hides_affordances_no_worker_probe` | T6 | `live_client_invoke_test.dart` | Flutter widget + integration (spy) | FR-008 / SC-004 — non-enrolled: no affordances; zero Worker probes |
| `degraded_unreachable_renders_normal_state_banner` | T7 | `live_client_invoke_test.dart` | Flutter widget + integration | FR-009 / SC-004 — unreachable → normal banner, not error dialog |
| `spy_production_mint_and_submit_ports_composed_on_hub` | T8 | `live_client_invoke_test.dart` | Flutter widget + integration (spy) | FR-010 / SC-005 — hub default composition wires production mint/submit ports |
| `live_idempotency_key_stable_for_single_user_action` | T9 | `live_client_invoke_test.dart` | Flutter widget + integration | FR-003 / SC-001 — idempotency key stable across transport retries |
| `discovery_auth_failure_taxonomy_no_manifest_body` | T10 | `live_client_invoke_test.dart` | Flutter widget + integration | FR-012 / SC-006 — discovery auth failure → taxonomy, no `{ manifests: … }`; suspended may yield `installation_suspended` |
| `live_host_contains_no_prompt_provider_or_model_identifiers` | T11 | `live_client_invoke_test.dart` (invokes E1 guard) | Architecture guard (R-12) | FR-013 / SC-007 — composition sources under this slice's paths pass E1 guard |

Every named test from the spec is placeable in §13.5 (widget/integration or Architecture guard). No named test is orphaned.

## Sequencing

1. **Tests first (or alongside)** — add `live_client_invoke_test.dart` with T1–T11 failing red against missing production adapters / unconfigured hub (never after implementation).
2. **Production mint adapter** — `supabase_aat_mint_port.dart` (FR-001).
3. **Production HTTPS submit adapter** — `https_submit_port.dart` (FR-001, FR-003, FR-004).
4. **Discovery client** — `discovery_client.dart` binding to I2 wire (FR-012); key extraction for Resolver (FR-002).
5. **Hub composition** — wire adapters + discovery keys into `_LiveVisitSummaryHost` / `AiFeatureHostDependencies`; enable live invoke; remove unconfigured stubs as defaults (FR-010, FR-008, FR-009, FR-014).
6. **Turn tests green** — T1–T10 behavioural; T11 architecture guard on composition paths.
7. **Verification** — slice-only `flutter test` for this file; confirm Consumes modules untouched.
8. **Documentation** — write `quickstart.md` per sections above.

## Complexity Tracking

> No constitution violations requiring justification. Empty by design.
