# Implementation Plan: `context_required` self-healing round trip (J2)

**Branch**: `ai/049-j2-context-required-self-healing` | **Date**: 2026-08-03 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/049-context-required-self-healing/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow. The AI platform variant adds five sections (`## Consumes Binding`, `## Components Touched`, `## Files`, `## Test Layout`, `## Sequencing`) and never produces `research.md`.

## Summary

J2 lands the Flutter client’s one automatic `context_required` self-healing round trip for
`single_shot` capabilities: on a typed missing-key rejection, refresh the manifest cache, resolve
the named keys through the existing Context Resolver, and resubmit **once** with the **same**
idempotency key; a second `context_required` for that action surfaces the request reference and
stops (no third attempt); conversational capabilities never enter this path (§8.4; §5.2 Self-healing).
It sits in band J after C2, E2, and E3 (`Needs: C2, E2, E3`); build when a client’s manifest cache
can be stale relative to the platform (delivery plan §3.9 row J2; DP-5).

## Technical Context

**Language/Version**: Dart (SDK `^3.11.5` as declared in `frontend/pubspec.yaml`); Flutter stable for
the Windows desktop client.

**Primary Dependencies**: Flutter desktop client under `frontend/`; C2-frozen `context_required`
missing-key manifest wire payload (`specs/026-context-validator-cost-preflight/contracts/context-validator.md`;
`ai-platform/src/context/validator.ts`); E2 AI Client SDK transport siblings under
`frontend/lib/core/ai/` (`AiClientSdk`, `HttpsSubmitPort`, `PlatformHttpException`, stable
idempotency key, request-reference retention); E3 Context Resolver key-list API
(`ContextResolver.resolve`, registration, provider port). Injectable `ManifestRefreshPort` for the
FR-003 refresh step (Clarification Q3). No Worker source changes, no Supabase schema/RPC changes, no
new pub packages (R-20).

**Storage**: N/A for durable stores — J2 defines no D1 entities and no clinic tables (spec Key
Entities: not applicable). Manifest refresh and Resolver cache remain ephemeral client concerns
(C1 discovery revalidation / E3 screen-scoped cache); no per-request server-side healing session
(§4.4, §9.7; §8.4).

**Testing**: Flutter integration (delivery plan §3.11.8 row J2; DP-3). Named cases 1–4 run via
`flutter test` against injectable SDK / Resolver / manifest-refresh fakes under
`frontend/test/unit/core/ai/` — no live Worker. Suite joins CI permanently (delivery plan §3.10).
Closest §13.5 client-side layers: Client contract tests / SDK integration behaviour (spec Test plan).

**Target Platform**: Flutter Windows desktop client (`frontend/`); clinic staff operators. AI remains
optional and additive; this slice adds no gateway stage.

**Project Type**: Client-side Flutter orchestration sibling under `frontend/lib/core/ai/` composing
SDK + Resolver + refresh (Clarification Q1) — not a gateway Worker slice, not a Supabase/RPC slice.
`AiClientSdk` stays transport-only.

**Performance Goals**: None beyond one client-driven refresh → resolve → resubmit. J2 adds no Quota
DO round trip, no D1 insert, and no R2 object; platform I/O budgets (§6.1, §7.5, §13.6) remain
untouched on the Worker side. Recovery is entirely client-driven from the typed rejection (§8.4).

**Constraints**: `single_shot` only (FR-001, FR-008). One automatic resubmission; second
`context_required` surfaces request reference; no third attempt (FR-005–FR-007). Same idempotency
key on resubmit (FR-005; E2 Freezes). Resolve named keys through existing E3 Resolver with no
capability branching (FR-004). Extend `PlatformHttpException` with optional C2 fields when
`code` is `context_required` (Clarification Q2) — extend, never rewrite C2 payload or E2 transport /
remint / general no-auto-retry. Injectable `ManifestRefreshPort` called once on heal (Clarification
Q3). No prompt/provider/model identifiers in Flutter (R-12; delivery plan §6.4). No per-request
server-side healing state (§4.4, §9.7).

**Scale/Scope**: One §4 component (§4.1 AI Client SDK — self-healing orchestration sibling;
`AiClientSdk` class remains transport-only). ~two Dart library touch points (`ports.dart` extend +
new sibling module), fakes extend, one Flutter test file for cases 1–4, named quickstart. Eight FRs.
Roughly 8–12 tasks — well under the ~25-task ceiling (delivery plan §6.3 / skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — one client
      round-trip recovers a stale desktop manifest cache without enterprise fleet management
      (constitution I; A12; spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — one Flutter orchestration sibling composing
      existing SDK + Resolver + refresh; no new deployable.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — J2 touches
      only `frontend/` (`lib/core/ai/` + tests). It does not add Worker stages or Supabase RPCs.
      Key resolution remains under caller RLS via E3. **§14 acknowledgement:** the gateway remains
      an additive, non-primary component with no domain logic, no business data, and no write path
      into Supabase; this slice does not expand that role (C2 already emits `context_required`;
      J2 does not change the Worker).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — J2 writes no clinic tables;
      Resolver reads continue under caller session/RLS (E3 Freezes; FR-004).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — AAT/submit remain E2; request reference retained for
      support display on the second `context_required`; soft-delete and clinic audit unchanged.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — first
      `context_required` recovers once; second surfaces the request reference rather than looping
      or failing opaquely; conversational flows excluded; clinical work continues without AI
      (constitution V; FR-006–FR-008).

## Project Structure

### Documentation (this feature)

```text
specs/049-context-required-self-healing/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify + /ai-platform-clarify (authoritative)
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — J2 defines no D1 (or other) entities (spec Key Entities: "Not
applicable").

`contracts/` is **not** produced — the **Freezes** entries are client behavioural rules (one
automatic self-heal round trip; one-resubmission bound; conversational exclusion). They introduce no
new wire shape (table, payload, token, event, or error taxonomy); the `context_required` missing-key
manifest remains C2’s frozen artifact. Later callers bind to the sibling module under
`frontend/lib/core/ai/`, not to a prose contract file. `research.md` is **not** produced — the
research is `docs/architecture/17-ai-platform.md`.

`quickstart.md` (written during the implement-phase Documentation task, per
`.specify/templates/ai-platform-quickstart-template.md`) will contain:

- **§1 Architecture context** — J2 row of the delivery plan (§3.9) and §8.4 / §5.2; what the spec
  delivered; what the plan scoped.
- **§2 What was implemented** — `single_shot` `context_required` self-heal (refresh → resolve → one
  same-key resubmit); second surfaces request reference; conversational exclusion;
  `PlatformHttpException` C2 optional fields; injectable `ManifestRefreshPort`.
- **§3 Files to review** — this slice’s `frontend/lib/core/ai/` and `frontend/test/unit/core/ai/`
  files only.
- **§5 Run the automated suite** — slice-only `flutter test` against this slice’s test file; no
  full-suite `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — open the self-heal sibling module, `PlatformHttpException` C2
  fields, and the focused test file; confirm E1 guard still covers `frontend/lib/core/ai/`.
- Manual validation omitted — CI / `flutter test` is the verification path (J2 exposes no new
  user-visible surface beyond request-reference surfacing already owned by feature surfaces).

### Source Code (repository root)

```text
frontend/
├── lib/
│   └── core/
│       └── ai/                                      # EXISTING E2/E3/H3 folder
│           ├── ai_client_sdk.dart                   # UNCHANGED — stays transport-only
│           │                                        #   (Clarification Q1)
│           ├── ports.dart                           # EXTEND — optional C2 fields on
│           │                                        #   PlatformHttpException when code is
│           │                                        #   context_required (Clarification Q2)
│           ├── taxonomy.dart                        # UNCHANGED — Consumes E2
│           ├── sse_events.dart                      # UNCHANGED — Consumes E2
│           ├── context_resolver.dart                # UNCHANGED — Consumes E3
│           ├── context_registration.dart            # UNCHANGED — Consumes E3
│           ├── context_provider_port.dart           # UNCHANGED — Consumes E3
│           ├── conversation_store.dart              # UNCHANGED — H3 (out of scope)
│           ├── conversation_loop.dart               # UNCHANGED — H3 (out of scope)
│           └── context_required_self_heal.dart      # NEW — ManifestRefreshPort + §8.4
│                                                    #   single_shot heal orchestration sibling
│                                                    #   (Clarification Q1, Q3)
├── test/
│   └── unit/
│       └── core/
│           └── ai/
│               ├── fakes.dart                       # EXTEND — context_required C2 fields on
│               │                                    #   SubmitHttpErrorStep; ManifestRefreshPort spy
│               └── context_required_self_heal_test.dart  # NEW — named tests 1–4
└── tool/
    └── architecture_guard/                          # UNCHANGED — R-12 / E1 (inherited)

# ai-platform/ and backend/ — UNCHANGED (Consumes C2 / E3 only; no rewrite)
```

**Structure Decision**: Self-healing orchestration lives as a **sibling module** under
`frontend/lib/core/ai/` composing SDK + Resolver + injectable manifest refresh; `AiClientSdk`
remains transport-only (Clarification Q1). `PlatformHttpException` gains optional C2 payload fields
so the heal path can read `missing_keys` / `shapes` / `manifest_version` /
`manifest_capability_id` after HTTP 422 (Clarification Q2) — an extension of the E2 error surface,
not a rewrite of C2’s wire payload. `ManifestRefreshPort` is injectable; production wires to C1
discovery revalidation, tests spy the single call (Clarification Q3). Same-action idempotency reuse
follows the ConversationLoop pattern: the heal helper owns a stable key factory for the action and
drives `AiClientSdk.invoke` without changing SDK remint / transport-retry / general no-auto-retry
rules. No `ai-platform/` or `backend/` path is modified.

## Consumes Binding

J2 has `Needs: C2, E2, E3` (delivery plan §3.9). Changing any is out of scope (delivery plan §2.3).

| Consumes entry | Existing module / file / type it binds to |
| --- | --- |
| **C2 — `context_required` rejection payload** (missing-key manifest: missing required keys with declared shapes, plus manifest version / capability id) | Frozen artifact `specs/026-context-validator-cost-preflight/contracts/context-validator.md` §4 (`missing_keys`, `shapes`, `manifest_version`, `manifest_capability_id` on the HTTP 422 body); implementation `ai-platform/src/context/validator.ts` (`ValidateResult` missing-keys branch, `buildContextRequiredResponse`). J2 wires client self-heal **against** that payload via optional fields on `PlatformHttpException` (Clarification Q2). It does **not** redefine validator rules, `context_invalid`, cost pre-flight, or the payload shape, and does not modify C2 modules. |
| **E2 — AI Client SDK** (submit path, stable client-generated idempotency key, SSE / terminal-state surfacing, request-reference retention; `context_required` surfaced without auto-resubmit) | `frontend/lib/core/ai/ai_client_sdk.dart`, `ports.dart` (`PlatformHttpException`, `HttpsSubmitPort`, `CapabilityInvokeInput`, `SubmitRequestHeaders`), `sse_events.dart`, `taxonomy.dart`; plan/spec `specs/036-ai-client-sdk/`. J2 **extends** `PlatformHttpException` with optional C2 fields when `code` is `context_required` (Clarification Q2) and adds a **sibling** heal module; `AiClientSdk` stays transport-only (Clarification Q1). It does **not** rewrite AAT acquire/cache, the `unauthenticated` re-mint path, general no-auto-retry for other taxonomy codes, or SSE framing (delivery plan §2.3; E2 Freezes / Out of Scope naming J2). |
| **E3 — Context Resolver registry** (generic key-list → assembled payload; no capability-id branching) | `frontend/lib/core/ai/context_resolver.dart` (`resolve(List<String> keys)`), `context_registration.dart`, `context_provider_port.dart`; frozen artifact `specs/037-context-resolver-registry/contracts/context-resolver.md`. J2 resolves keys named by `context_required.missing_keys` through that API. It does **not** redefine the registry API, screen-scoped cache, or provider RPCs (E3 Freezes; E3 Out of Scope naming J2). |

No Consumes entry lacks an existing implementation. None is rewritten beyond the reserved
`PlatformHttpException` optional-field extension (delivery plan §2.3). Stop condition 2 is not
triggered.

## Components Touched

J2 modifies **one** §4 component: **§4.1 AI Client SDK** (self-healing path as a sibling
orchestration module; transport class unchanged).

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.1 AI Client SDK | **Extended** | Sole deliverable — §8.4 `single_shot` self-heal sibling under `frontend/lib/core/ai/`; optional C2 fields on `PlatformHttpException`; `AiClientSdk` remains transport-only (Clarification Q1; delivery plan §3.9 row J2). |
| §4.1 Context Resolver | **Not touched** | Consumes E3 only — heal calls existing `resolve(keys)`. |
| §4.1 AI Feature Surfaces | **Not touched** | E4 — request-reference display already exists; J2 surfaces the reference through the heal outcome for callers. |
| §4.1 Conversation store | **Not touched** | H band; conversational exclusion (FR-008). |
| §4.2–§4.5 / §4.3.* gateway stages | **Not touched** | Out of scope; Consumes C2 payload only. |

Exactly one §4 component — stop condition 5 (multi-component without reason) is not triggered.

## Files

| File | FR(s) | Status |
| --- | --- | --- |
| `frontend/lib/core/ai/ports.dart` | FR-002 | EXTEND — optional C2 fields on `PlatformHttpException` (`missingKeys` / `shapes` / `manifestVersion` / `manifestCapabilityId`, mirroring wire `missing_keys`, `shapes`, `manifest_version`, `manifest_capability_id`) when `code` is `context_required` (Clarification Q2). Existing callers omit the fields. |
| `frontend/lib/core/ai/context_required_self_heal.dart` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008 | NEW — injectable `ManifestRefreshPort` (Clarification Q3) + `single_shot`-only heal helper: on first `context_required`, refresh once → resolve `missing_keys` via E3 → resubmit once with the **same** idempotency key; on second `context_required`, stop and surface request reference (no third attempt); refuse conversational `interaction_mode` (Clarification Q1). |
| `frontend/test/unit/core/ai/fakes.dart` | FR-002–FR-007 (test support) | EXTEND — `SubmitHttpErrorStep` / `PlatformHttpException` can carry C2 missing-key fields; `ManifestRefreshPort` spy recording call count. |
| `frontend/test/unit/core/ai/context_required_self_heal_test.dart` | FR-001–FR-008; tests 1–4 | NEW — Flutter integration suite for all named tests (delivery plan §3.11.8 J2). Joins CI permanently (delivery plan §3.10). |
| `specs/049-context-required-self-healing/quickstart.md` | — | NEW — written during the implement-phase Documentation task (sections named in Project Structure → Documentation). |

Every file traces to an `FR-###` (or the deferred Documentation task). No file is created for an
unstated requirement. No `ai-platform/` or `backend/` file is touched. No Consumes module is
rewritten beyond the reserved optional-field extension.

## Test Layout

The spec’s Test plan names four tests at layer **Flutter integration** (delivery plan §3.11.8 row
J2). That is the client Flutter test suite (DP-3); the closest §13.5 client-side layers are Client
contract tests / SDK integration behaviour (spec Test plan). Tests join CI permanently (delivery
plan §3.10). All cases live under `frontend/test/unit/core/ai/context_required_self_heal_test.dart`
and run with injectable fakes — no live Worker.

| # | Test name | Spec layer | Where it lives | Asserts |
| --- | --- | --- | --- | --- |
| 1 | `stale_client_context_required_refreshes_resolves_resubmits_once_same_idempotency_key_and_succeeds` | Flutter integration | `context_required_self_heal_test.dart` | Refresh spy called once; Resolver receives missing keys; exactly one automatic resubmit; same idempotency key; success through normal pipeline (FR-002–FR-005; SC-001) |
| 2 | `second_context_required_stops_and_surfaces_request_reference` | Flutter integration | `context_required_self_heal_test.dart` | After one heal resubmit, second `context_required` stops automatic recovery and surfaces request reference (FR-006; SC-002) |
| 3 | `no_automatic_third_attempt_after_second_context_required` | Flutter integration | `context_required_self_heal_test.dart` | Submit/refresh/resolve spy counts prove no third automatic attempt (FR-007; SC-003) |
| 4 | `conversational_capabilities_never_take_context_required_self_heal_path` | Flutter integration | `context_required_self_heal_test.dart` | `interaction_mode: conversational` never enters §8.4 heal (no refresh / resolve / same-key resubmit path) (FR-001, FR-008; SC-004) |

Every named test places in the Flutter integration layer — stop condition 3 not triggered. Coverage
matches delivery plan §3.10 / §3.11.8 J2 (happy path, second-rejection bound, no third attempt,
conversational exclusion) plus inherited prohibitions (no server healing session; no
prompt/provider/model in Flutter via E1 coverage of `lib/core/ai/`).

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2). Within this
slice:

1. **`PlatformHttpException` C2 fields (Clarification Q2; FR-002)** — extend `ports.dart`; extend
   fakes so HTTP-error steps can emit the missing-key manifest.
2. **`ManifestRefreshPort` + heal scaffolding (Clarification Q1, Q3; FR-001, FR-003)** — land
   `context_required_self_heal.dart` with the injectable refresh port and `single_shot` gate;
   red/green conversational exclusion (test 4) alongside.
3. **Refresh → resolve → one same-key resubmit (FR-003–FR-005; test 1)** — wire C2 fields →
   `ManifestRefreshPort` once → `ContextResolver.resolve(missing_keys)` → resubmit with stable
   idempotency key factory; land test 1.
4. **One-resubmission bound + no third attempt (FR-006–FR-007; tests 2–3)** — second
   `context_required` surfaces request reference; spy proves no further automatic submit/refresh/
   resolve; land tests 2–3.
5. **R-12 inheritance** — confirm new paths under `frontend/lib/core/ai/` remain covered by the E1
   architecture guard (no prompts/providers/models).
6. **Documentation** — fill `quickstart.md` after implementation and verification (sections named
   above).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations. Table omitted.
