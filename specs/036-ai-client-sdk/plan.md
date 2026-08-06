# Implementation Plan: AI Client SDK (E2)

**Branch**: `ai/036-e2-ai-client-sdk` | **Date**: 2026-08-02 | **Spec**: [`spec.md`](./spec.md)

**Input**: Feature specification from `specs/036-ai-client-sdk/spec.md`

**Note**: This template is filled in by the `/ai-platform-plan` command. See `.specify/templates/plan-template.md` for the execution workflow.

## Summary

E2 lands the Flutter **AI Client SDK** as the transport-only §4.1 client component: acquire and cache an AAT (single-flight), re-mint once on `unauthenticated`, submit with a stable idempotency key (per-invoke override), consume the A6 SSE stream via internal rebroadcast to exactly one terminal (or typed `StreamDroppedTerminal`), surface terminal state, cancel by closing the stream with local `CancelledTerminal`, retain the last request reference, retry transport errors within a bounded ceiling, map unknown taxonomy codes to `internal_error` via `fromWire`, and never auto-retry after a terminal platform error — with no prompts, providers, or models in the client (R-12; E1). It sits in Band E after E1 / A6 / C1 (`Needs: E1, A6, C1`) and freezes the shared transport E3 and E4 will call.

## Technical Context

**Language/Version**: Dart (SDK `^3.11.5` as declared in `frontend/pubspec.yaml`); Flutter stable for the Windows desktop client.

**Primary Dependencies**: The Flutter desktop client under `frontend/`; frozen wire and taxonomy contracts from A6 / A2 (SSE framing, submit headers, §5.4 codes and error body) and capability identity from C1 (capability id + version pin on submit); clinic AAT mint path already frozen by Band B (Assumptions — callable mint; E2 does not re-implement issuance). Injectable mint / HTTPS-submit / SSE ports with in-memory fakes for tests (Clarification Q2). No Worker source changes, no Supabase schema/RPC changes, no new pub packages required by the spec.

**Storage**: N/A for durable stores — E2 defines no D1 entities and no clinic tables (spec Key Entities: not applicable). Ephemeral in-process only: cached AAT while accepted by the platform, and the last request reference held for support (§4.1; FR-003, FR-009).

**Testing**: Flutter unit + integration (delivery plan §3.11.5 row E2; DP-3). Named cases T1–T28 run via `flutter test` against injectable in-memory fakes/spies that emit canned A6 sequences and §5.4 codes — no live Worker (Clarification Q2; Assumptions). Suite joins CI permanently (delivery plan §3.10). T28 additionally proves SDK sources under `frontend/` pass the E1 architecture guard (R-12).

**Target Platform**: Flutter Windows desktop client (`frontend/`); clinic staff operators; AI remains optional and additive (spec Assumptions).

**Project Type**: Client-side Flutter transport module under `frontend/lib/core/ai/` (Clarification Q1) — not a gateway Worker slice, not a Supabase/RPC slice.

**Performance Goals**: None beyond ordinary client transport. E2 adds no Quota DO round trip, no D1 insert, and no R2 object; platform I/O budgets (§6.1, §7.5, §13.6) remain untouched on the Worker side. Numeric cache TTL is not invented here; transport-retry ceiling/backoff/exhaustion are Clarification Session 2026-08-05 (spec Assumptions).

**Constraints**: Transport-only (§4.1 Must not: interpret/transform model output; decide model/provider; embed prompt fragments; retry after a *terminal* platform error). One silent re-mint on `unauthenticated`, no remint loop; single-flight mint (FR-004; §5.4; Clarification Session 2026-08-05). Stable client-generated idempotency key across transport retries; per-invoke `idempotencyKey?` / `cancelSignal?` (FR-005). SSE rules 1–5 for the surfaces E2 owns — open on `accepted`, typed content/heartbeats, exactly one wire terminal among `completed` / `failed` / `cancelled`; cancel = stream close + local `CancelledTerminal`; drop without terminal → `StreamDroppedTerminal`; session rebroadcasts events (FR-006–FR-008; Clarification Session 2026-08-05; single-shot freeze — H-band members postdate E2 per §2.3). Unknown taxonomy code → `internal_error` via `FailedEvent.fromWire` (FR-010). Must pass E1 guard and must not weaken it (FR-012; Consumes E1). No discovery UX, Context Resolver, feature surface, or conversational path as E2 scope (Out of Scope E3/E4/H).

**Scale/Scope**: One §4.1 component (AI Client SDK); ~four Dart library files under `frontend/lib/core/ai/` plus Flutter unit/integration tests for T1–T28 (T7–T23 share one parameterized no-auto-retry suite). Twelve FRs. Well under the ~25-task ceiling when terminal no-retry cases are one task family (delivery plan §6.3 stop condition 5 / skill stop condition 5). Touches exactly one §4 component (see Components Touched).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — transport-only
      Flutter SDK; no clinic-operated AI infrastructure (§4.1; spec Clinic Fit).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — client library only; no new deployable.
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — E2 touches
      only `frontend/` (`lib/core/ai/` + tests). It does not add Worker stages or Supabase RPCs.
      The gateway remains the additive, non-primary §14 component (no domain logic, no business
      data, no write path into Supabase); the SDK respects that boundary by never embedding AI
      business rules, prompts, providers, or models in Flutter (§4.1; §14; spec Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — E2 writes no clinic
      tables, does not mint scopes, and does not bypass RLS (context assembly is E3; acceptance
      is F2 / E4).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — SDK carries AAT and §5.5 headers; request
      references retained only for support display; soft-delete and clinic audit unchanged.
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — SDK surfaces
      transport/terminal failures to the caller; degraded/non-enrollment UX is E4 (Out of Scope);
      no auto-commit of AI output; provisional content is not assembled into a final result (FR-002;
      T27; delivery plan §6.4).

## Project Structure

### Documentation (this feature)

```text
specs/036-ai-client-sdk/
├── plan.md              # This file
├── spec.md              # /ai-platform-specify output (authoritative)
└── quickstart.md        # Written during the implement-phase Documentation task (sections below)
```

`data-model.md` is **not** produced — E2 defines no D1 (or other) entities (spec Key Entities: "Not applicable").

`contracts/` is **not** produced — the **Freezes** entries are client behavioural rules (SDK transport surface, AAT acquire-and-cache / remint ceiling, stable idempotency key, client-side SSE consumption, no-auto-retry-after-terminal, unknown→`internal_error`). They introduce no new wire shape (table, payload, token, event, or error taxonomy); those remain A6 / A2 / C1 / B1. Later slices (E3, E4, H3, J2) bind to the SDK module under `frontend/lib/core/ai/`, not to a prose contract file. `research.md` is **not** produced — the research is `docs/architecture/ai-platform/01-ai-platform.md`.

`quickstart.md` (written during the implement-phase Documentation task, per `.specify/templates/ai-platform-quickstart-template.md`) will contain:

- **§1 Architecture context** — E2 row of the delivery plan (§3.6) and §4.1 / §5.5 / §5.4; what the spec delivered; what the plan scoped.
- **§2 What was implemented** — the AI Client SDK (AAT cache/remint/single-flight, idempotent submit with retry ceiling, SSE consume-to-terminal / drop / local cancel, event rebroadcast, last request-reference retention, taxonomy mapping via `fromWire`).
- **§3 Files to review** — this slice's `frontend/lib/core/ai/` and `frontend/test/unit/core/ai/` files only.
- **§5 Run the automated suite** — slice-only `flutter test` commands against this slice's test files; no full-suite `npm test`, no combined prior-slice counts.
- **§6 Inspect the changes** — open the SDK module, taxonomy mapping, and a focused test file; confirm E1 guard still covers `frontend/lib/core/ai/`.
- Manual validation omitted — CI / `flutter test` is the verification path (E2 exposes no user-visible surface; E4 does).

### Source Code (repository root)

```text
frontend/
├── lib/
│   └── core/
│       └── ai/                                    # NEW — AI Client SDK root (Clarification Q1)
│           ├── ai_client_sdk.dart                 # NEW — transport SDK: submit, cache, remint,
│           │                                      #   bounded retry, cancel, rebroadcast session,
│           │                                      #   last request reference
│           ├── ports.dart                         # NEW — injectable mint / HTTPS submit / SSE
│           │                                      #   ports (Clarification Q2); may be single-sub
│           ├── taxonomy.dart                      # NEW — §5.4 closed set + unknown→internal_error
│           └── sse_events.dart                    # NEW — client-side A6 event kinds / terminal
│                                                  #   state as received; fromWire; drop terminal
├── test/
│   └── unit/
│       └── core/
│           └── ai/                                # NEW — Flutter unit + integration suite
│               ├── fakes.dart                     # NEW — in-memory mint/submit/SSE fakes/spies
│               └── ai_client_sdk_test.dart        # NEW — T1–T28
└── tool/
    └── architecture_guard/                        # UNCHANGED — Consumes E1; T28 must still pass

# ai-platform/ and backend/ — UNCHANGED (Consumes only; no rewrite)
```

**Structure Decision**: The SDK lives under `frontend/lib/core/ai/` beside other core transport/orchestration code (Clarification Q1). Tests and in-memory fakes live under `frontend/test/unit/core/ai/` and drive the SDK through injectable ports — no network (Clarification Q2). No `ai-platform/` or `backend/` path is modified. Consumed wire/taxonomy/capability contracts stay in their existing modules and frozen artifacts; the Dart taxonomy mirror and SSE event types are client-side bindings that add no codes and change no A6 framing.

## Consumes Binding

E2 has `Needs: E1, A6, C1` (delivery plan §3.6). It also Consumes **A2 via A6** (error taxonomy). Changing any is out of scope (delivery plan §2.3).

| Consumes entry | Existing module / file / type it binds to |
| --- | --- |
| **E1 — Client architecture guard (R-12)** | `frontend/tool/architecture_guard/architecture_guard.dart` (standalone CI lint; default scan roots include `lib` and `test`) and the dedicated architecture-guard step(s) in `.github/workflows/ci.yml`. E2 adds SDK sources under `frontend/lib/core/ai/` that must remain free of prompt-like strings, provider names, and model identifiers (FR-012; T28). E2 does not weaken, bypass, relocate, or alter the guard script or CI step. |
| **A6 — Protocol adapter and SSE framing** (§4.3.1, §5.5) | Frozen artifact `specs/020-ai-protocol-adapter-sse/contracts/sse-framing.md`; implementation `ai-platform/src/adapter.ts`. Bindings used by the SDK as a **client**: submit-request headers `x-idempotency-key`, `x-trace-id`, `x-capability-version`; SSE vocabulary `accepted` / heartbeat / typed content / `completed` / `failed` / `cancelled`; one-terminal-event invariant; connection-scoped cancel by closing the stream; on-the-wire §5.4 HTTP mapping and A2 error body on failures. E2 does not redefine event kinds, headers, or the terminal rule and does not modify `adapter.ts`. |
| **A2 via A6 — Error taxonomy and diagnostic envelope** (§5.4) | `ai-platform/src/errors.ts` — `TaxonomyCode` closed union, `TAXONOMY` table, `classifyErrorCode` / `isTaxonomyCode` (unknown → `internal_error`), `buildErrorBody` shape `{"code","request_reference","trace_id","retry_safe"}`. Surfaced on the wire through A6. E2's Dart `taxonomy.dart` mirrors the closed set and the unknown→`internal_error` rule for client branching (FR-010); it adds no codes and changes none. |
| **C1 — Capability registry, resolver, and discovery** (§4.3.4, §5.1, §5.5) | Frozen artifact `specs/025-capability-resolver-discovery/contracts/capability-registry.md`; implementation `ai-platform/src/capability/index.ts` (`CapabilityRegistry`, `resolve`, `discover`, registry key `<capabilityId>@<version>`). E2 submits capability id + version pin on the A6 submit surface (FR-006); it does not implement discovery UX, the Context Resolver, or client-side capability branching, and does not modify C1 modules. |

No Consumes entry lacks an existing implementation. None is modified (delivery plan §2.3). Stop condition 2 is not triggered.

## Components Touched

E2 modifies **one** §4 component: **§4.1 AI Client SDK**.

| §4 component | Touched? | Reason |
| --- | --- | --- |
| §4.1 AI Client SDK | **Created** | This slice's sole deliverable — transport concern only (§4.1 table; delivery plan §3.6 row E2). |
| §4.1 Context Resolver | **Not touched** | E3 |
| §4.1 AI Feature Surfaces | **Not touched** | E4 |
| §4.1 Conversation store | **Not touched** | H band |
| §4.2–§4.5 / §4.3.* gateway stages | **Not touched** | Out of scope; Consumes A6/C1/A2 only |

Exactly one §4 component — stop condition 5 (multi-component without reason) is not triggered.

## Files

| File | FR(s) | Status |
| --- | --- | --- |
| `frontend/lib/core/ai/ports.dart` | FR-001, FR-003, FR-006 | NEW — injectable ports for AAT mint, HTTPS submit, and SSE stream open/close (Clarification Q2). Events may be single-subscription; SDK rebroadcasts. `TransportRetryExhausted` / submit-phase cancel types live here. No second cancel endpoint. |
| `frontend/lib/core/ai/taxonomy.dart` | FR-010, FR-011 | NEW — Dart mirror of the §5.4 closed code set; `classifyTaxonomyCode` maps any code outside the set to `internal_error`; used for branching and for proving no auto-retry after each terminal code (except the `unauthenticated` remint path). |
| `frontend/lib/core/ai/sse_events.dart` | FR-006, FR-007 | NEW — client-side A6 event kinds and terminal outcomes as received (`completed` / `failed` / local `CancelledTerminal` / `StreamDroppedTerminal`); `FailedEvent.fromWire` applies `classifyTaxonomyCode`; no reshape of model output (FR-002; T27). H-band `ContextRequested*` members postdate E2 (§2.3). |
| `frontend/lib/core/ai/ai_client_sdk.dart` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009, FR-011, FR-012 | NEW — AI Client SDK: single-flight acquire/cache AAT; remint once on `unauthenticated` (no loop); `Random.secure()` ≥128-bit keys/trace ids; `invoke({idempotencyKey?, cancelSignal?})`; transport retry ≤3 with backoff/jitter → `TransportRetryExhausted`; consume SSE via internal rebroadcast to exactly one terminal (or `StreamDroppedTerminal` on silence/drop); cancel closes stream + synthesizes `CancelledTerminal`; retain last request reference; never auto-retry after terminal taxonomy outcomes other than the single remint path. |
| `frontend/test/unit/core/ai/fakes.dart` | FR-001–FR-011 (test support) | NEW — in-memory mint / HTTPS submit / SSE fakes and spies emitting canned A6 sequences and §5.4 codes (Clarification Q2). |
| `frontend/test/unit/core/ai/ai_client_sdk_test.dart` | FR-001–FR-012; T1–T28 | NEW — Flutter unit + integration suite for all named tests; T7–T23 as one parameterized family. Joins CI permanently (delivery plan §3.10). |
| `specs/036-ai-client-sdk/quickstart.md` | — | NEW — written during the implement-phase Documentation task (sections named in Project Structure → Documentation). |

Every file traces to an `FR-###` (or the deferred Documentation task). No file is created for an unstated requirement. No `ai-platform/` or `backend/` file is touched. No Consumes module is rewritten.

## Test Layout

The spec's Test plan names twenty-eight tests at layer **Flutter unit + integration** (delivery plan §3.11.5 row E2). That is the client Flutter test suite (DP-3); §13.5's client-side rows (Architecture guard for T28's R-12 inheritance; Client contract tests belong to E3) do not replace this layer. Tests join CI permanently (delivery plan §3.10). All cases live under `frontend/test/unit/core/ai/` and run with injectable fakes — no live Worker (Clarification Q2).

| Test name | Spec layer | Where it lives | Asserts |
| --- | --- | --- | --- |
| `sdk_aat_acquired_and_cached` | Flutter unit + integration | `ai_client_sdk_test.dart` | Token acquired and cached; second submit reuses cache without a second mint while valid (T1) |
| `sdk_unauthenticated_remints_once_then_succeeds` | Flutter unit + integration | `ai_client_sdk_test.dart` | One remint + one retry on `unauthenticated`, then success; spy counts (T2) |
| `sdk_unauthenticated_no_remint_loop` | Flutter unit + integration | `ai_client_sdk_test.dart` | Second `unauthenticated` after remint is surfaced; no further mint (T3) |
| `sdk_idempotency_key_stable_across_transport_retries` | Flutter unit + integration | `ai_client_sdk_test.dart` | Same idempotency key on every transport retry of one action (T4) |
| `sdk_stream_consumed_to_terminal_event` | Flutter unit + integration | `ai_client_sdk_test.dart` | `accepted` → exactly one terminal; silence/drop → `StreamDroppedTerminal` (T5) |
| `sdk_cancel_closes_stream` | Flutter unit + integration | `ai_client_sdk_test.dart` | Cancel closes stream + local `CancelledTerminal`; no separate cancel endpoint (T6) |
| `sdk_no_retry_after_installation_suspended` … `sdk_no_retry_after_internal_error` | Flutter unit + integration | `ai_client_sdk_test.dart` (parameterized T7–T23) | One case per terminal §5.4 code (other than remint path): no auto-retry |
| `sdk_last_request_reference_retained` | Flutter unit + integration | `ai_client_sdk_test.dart` | Last request reference retained for support (T24) |
| `sdk_unknown_error_code_treated_as_internal_error` | Flutter unit + integration | `ai_client_sdk_test.dart` | Unknown code → `internal_error` (T25) |
| `sdk_transport_retry_allowed` | Flutter unit + integration | `ai_client_sdk_test.dart` | Transport retry within ceiling + same key; exhaustion → `TransportRetryExhausted` (T26) |
| `sdk_does_not_interpret_model_output` | Flutter unit + integration | `ai_client_sdk_test.dart` | Listens to rebroadcast events; terminal payload as received; no reshape (T27) |
| `sdk_contains_no_prompt_provider_or_model_identifiers` | Flutter unit + integration | `ai_client_sdk_test.dart` (+ E1 guard on SDK paths) | SDK sources pass E1 architecture guard (T28) |

Every named test places in the Flutter unit + integration layer — stop condition 3 not triggered. Coverage matches delivery plan §3.10 / spec Coverage paragraph (happy paths, every terminal taxonomy code this slice can surface, remint branches, unknown mapping, cancel, transport retry, R-12 / no client-side assembly).

## Sequencing

Tests land first or alongside their implementation, never after (delivery plan §2.2). Within this slice:

1. **Ports + fakes (Clarification Q2; FR-001 foundation)** — land `ports.dart` and `fakes.dart` so subsequent cases can drive mint/submit/SSE without a network (single-subscription ports OK; SDK rebroadcasts).
2. **Taxonomy mirror (FR-010; T25)** — land `taxonomy.dart` with the closed set and `classifyTaxonomyCode`; prove T25 alongside.
3. **SSE event types (FR-006, FR-007; T5, T27)** — land `sse_events.dart` including `FailedEvent.fromWire`, `CancelledTerminal`, `StreamDroppedTerminal`; prove stream-to-terminal / drop / listen-on-rebroadcast.
4. **AAT acquire/cache + remint (FR-003, FR-004; T1–T3)** — implement single-flight cache and one-shot remint in `ai_client_sdk.dart`; land T1–T3 alongside.
5. **Submit + stable idempotency + bounded transport retry (FR-005, FR-006, FR-001; T4, T26)** — wire submit with per-invoke key override, `maxTransportAttempts=3` + backoff, `TransportRetryExhausted`, `cancelSignal`; land T4 and T26.
6. **Stream consume, terminal surface, local cancel, last reference (FR-007, FR-008, FR-009; T5, T6, T24)** — rebroadcast session lifecycle; synthesize `CancelledTerminal` on cancel; land T5, T6, T24.
7. **No auto-retry after terminal taxonomy outcomes (FR-002, FR-011; T7–T23)** — parameterized suite, one case per code other than the remint path.
8. **R-12 / Must-not interpret (FR-002, FR-012; T27–T28)** — T27 listens to rebroadcast events; prove no reshape and E1 guard pass.
9. **Documentation** — fill `quickstart.md` after implementation and verification (sections named above).

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

No constitution violations. Table omitted.
