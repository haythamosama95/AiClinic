# Implementation Plan: Conversational journaling and client chat surface (H3)

**Branch**: `ai/046-h3-conversational-journaling` | **Date**: 2026-08-02 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/046-conversational-journaling/spec.md`

**Note**: Filled in by the `/ai-platform-plan` command. The AI platform variant adds five sections (`## Consumes Binding`, `## Components Touched`, `## Files`, `## Test Layout`, `## Sequencing`) and never produces `research.md`.

## Summary

H3 populates the A5-reserved nullable `conversation_id` and `turn_ordinal` columns on each
conversational leg's ordinary `ai_request` row so a whole conversation is readable with one query
grouped and ordered by those fields; proves each leg is independently admitted, journaled, and
credited (including crediting a `context_requested` / `AwaitingContext` leg with actual usage)
without a conversation table or per-request server state; and lands the Flutter Conversation store
plus chat negotiation loop that holds and resupplies the transcript, resolves `context_requested`
keys through the existing E3 Resolver with no capability branching, uses a new idempotency key per
leg, discards the transcript on close, and keeps cancellation connection-scoped to one leg. It sits
in band H after C3, E2, E3, and H1 so journaling and the client loop bind to frozen journal, SDK,
Resolver, and conversational-terminal artifacts (delivery plan §3.8, row H3).

## Technical Context

**Language/Version**: TypeScript 5.9 in the Cloudflare Worker (`ai-platform/`), Node ≥22 for the
toolchain (`ai-platform/package.json`); Dart (SDK `^3.11.5` as declared in `frontend/pubspec.yaml`)
and Flutter stable for the Windows desktop Conversation store / negotiation loop.

**Primary Dependencies**: Existing modules — C3 `ai-platform/src/journal/index.ts`
(`createRequestRow` already accepts optional `conversationId` / `turnOrdinal`; stage-15/16 +
get-request unchanged); B4 admission/credit (`src/admission/`, `src/credit/`, `src/quota-do/`);
fake provider (`src/provider/fake.ts`); E2 `frontend/lib/core/ai/` SDK (`AiClientSdk`,
`CapabilityInvokeInput`, SSE terminals); E3 `ContextResolver` / registration / provider port; H1
conversational manifest fields, `context_requested` terminal, `AwaitingContext`, platform-owned
`{key, arguments}` schema. Vitest ~3.2 (workers pool for D1/DO/R2) and `flutter test`. No new
runtime dependency (R-20).

**Storage**: No new D1 entity and no schema migration (FR-002, FR-004, FR-015; delivery plan §3.8
Useful to know — columns reserved in A5). H3 populates existing nullable `conversation_id` /
`turn_ordinal` on `ai_request` and reads them with the A5-documented query pattern
`WHERE conversation_id = ? ORDER BY turn_ordinal`. Exactly one R2 envelope per leg remains C3's
rule; H3 adds no second R2 object and no conversation/session store. Client transcript is
ephemeral in-process state discarded on close (§4.1; FR-012).

**Testing**: Integration (spy) + Flutter (delivery plan §3.11.7 row H3; §13.5 Pipeline tests and
client Flutter suite). Journaling cases: full pipeline integration submitting conversational legs
with fake provider + admission/credit/R2 spies, then asserting D1 rows / ordered conversation query
/ no conversation table or per-request state (Clarification Session 2026-08-02 Q3). Client cases:
`flutter test` against injectable SDK/Resolver fakes under `frontend/test/unit/core/ai/`. Slice-only
commands; suite joins CI permanently (delivery plan §3.10).

**Target Platform**: `ai-platform/` Cloudflare Worker (journaling / independent admit-credit) and
Flutter Windows desktop client (`frontend/`) for the Conversation store and chat loop. No
`backend/` schema or RPC changes — context resolution continues via existing E3 read RPCs under
caller RLS (spec Layer Placement).

**Project Type**: Dual-layer additive slice — Worker journal population/query helpers plus Flutter
§4.1 Conversation store / negotiation loop beside E2/E3 under `frontend/lib/core/ai/`
(Clarification Q1). §14 acknowledgement: Worker remains non-primary, no domain logic, no business
data, no write path into Supabase.

**Performance Goals**: Preserve platform I/O budgets — one Quota DO admission + one credit settle
per leg, one D1 insert at stage 9, one R2 object per leg (§6.1, §7.5, §13.6; FR-015). No second DO
round trip and no second R2 object from H3. Client holds transcript locally with no platform session.

**Constraints**: Extension only of C3/E2/E3/H1 Freezes — no rewrite of journal lifecycle,
one-envelope rule, get-request, SDK transport/remint/terminal-retry, Resolver key-list /
no-capability-id rule, or H1 manifest/schema/terminal contracts (delivery plan §2.3). Optional
conversational fields on existing `CapabilityInvokeInput` (`conversationId`, `turnOrdinal`,
`transcript`); omitted/null for `single_shot` (Clarification Q2). Store + negotiation loop under
`frontend/lib/core/ai/`; optional widget/host chrome under `features/ai/` for tests only
(Clarification Q1). No new pipeline stage, no conversation entity, no per-request server state, no
new taxonomy codes (FR-015; Edge Cases). `single_shot` acquires no Conversation store behaviour
(FR-018). No prompt/provider/model identifiers in Flutter (FR-016; R-12).

**Scale/Scope**: Three §4 component surfaces (journal writer population/query, Conversation store
+ loop, AI Client SDK conversational invoke/terminal extension) — see Components Touched for the
multi-component reason. Roughly 20–24 tasks when journaling pipeline tests and Flutter store/loop
tests are colocated into two primary test files — under the ~25-task ceiling (delivery plan §6.3 /
skill stop condition 5).

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- [x] Feature scope still fits small-to-mid-size multi-branch clinics; hospital-scale or
      enterprise-only requirements are explicitly rejected or separately ratified — multi-turn chat
      without a session store or conversation entity; only two nullable journal columns and a
      client-held transcript (spec Clinic Fit; §7.3; §6.7.1).
- [x] Design keeps a simple operational model with no microservices, message queues,
      Kubernetes, or custom primary backend service — extends existing Worker journal helpers and
      Flutter core AI modules; no new deployable, queue, or stateful component beyond the Quota DO
      (FR-015).
- [x] Layer ownership is explicit: Flutter handles UI/orchestration, Supabase handles
      backend capabilities, PostgreSQL owns domain integrity, and AI stays isolated — journaling in
      `ai-platform/`; Conversation store / loop in `frontend/`; `backend/` unchanged for this slice;
      Resolver reads remain caller-RLS clinic RPCs (spec Layer Placement).
- [x] Protected writes, validation, permissions, and transactional rules remain enforced
      through PostgreSQL constraints, triggers, RLS, or RPC functions — H3 opens no Supabase write
      path from the gateway; context authorization remains the user's own RLS on Resolver reads
      (FR-017; §8.10; §14).
- [x] Security remains authenticated, tenant-scoped, branch-scoped, permission-gated,
      auditable, and soft-delete-preserving — each leg independently authenticated/admitted/
      journaled; clinic data reach is permitted-key set ∩ user RLS; soft-delete and clinic audit
      unchanged (FR-006, FR-017).
- [x] AI actions remain human-approved, have no direct database/backend access, and the
      feature still works in a degraded manual mode when AI is unavailable — platform never fetches
      clinic data; cancelling one leg leaves the conversation on the client; `single_shot` and
      non-AI clinics remain unaffected (FR-014, FR-018; constitution V; A11).

**§14 acknowledgement (gateway slice):** The Worker is an additive, non-primary component with no
domain logic, no business data, and no write path into Supabase. H3 populates reserved journal
columns and adds no domain logic, no business data, no conversation table, and no Supabase write
path.

## Project Structure

### Documentation (this feature)

```text
specs/046-conversational-journaling/
├── plan.md                              # This file
├── spec.md                              # /ai-platform-specify + /ai-platform-clarify (already present)
├── contracts/
│   └── conversational-journaling.md     # Frozen: column write + ordered conversation query +
│                                        #   independent admit/credit / no conversation entity
└── quickstart.md                        # Named here; filled during Documentation after verification
```

`data-model.md` is omitted — H3 defines no D1 entity; columns were reserved in A5 (spec Key Entities;
FR-002, FR-004).
`research.md` is never produced — the research is `docs/architecture/17-ai-platform.md` (delivery plan §6).

**`quickstart.md` sections (to fill after implementation + verification):** Architecture context
(H3 row §3.8; §7.3 / §6.7.1 / §8.10 / §4.1 / §6.7); What was implemented (journal column population
+ ordered conversation query; Conversation store + negotiation loop; SDK optional invoke fields /
`context_requested` client terminal); Files to review (this slice only); Run the automated suite
(`npx vitest run` against this slice's workers-pool journaling test file; `flutter test` against
this slice's Flutter test files); Inspect the changes. Manual validation omitted — CI / vitest /
flutter test is the verification path for this slice's automated Done when.

### Source Code (repository root)

```text
ai-platform/
├── src/
│   ├── journal/
│   │   └── index.ts              # MODIFIED — ensure conversational legs write client-supplied
│   │                             #   conversation_id / turn_ordinal (C3 already accepts inputs);
│   │                             #   add listConversationLegs(conversationId) one-query helper
│   │                             #   WHERE conversation_id = ? ORDER BY turn_ordinal;
│   │                             #   AwaitingContext terminal path unchanged (H1/C3)
│   ├── admission/                # CONSUMED (B4) — per-leg admission; unchanged
│   ├── credit/                   # CONSUMED (B4) — per-leg credit including context_requested; unchanged
│   ├── provider/fake.ts          # CONSUMED — fake provider for full-pipeline integration; unchanged
│   └── quota-do/                 # CONSUMED — Quota DO; unchanged
└── test/
    └── conversational-journaling.test.ts  # NEW — full pipeline integration (spy) named tests
                                           #   (Clarification Q3); workers-pool config include

frontend/
├── lib/
│   └── core/
│       └── ai/                                      # EXISTING E2/E3 folder (Clarification Q1)
│           ├── ports.dart                           # MODIFIED — optional conversationId,
│           │                                        #   turnOrdinal, transcript on
│           │                                        #   CapabilityInvokeInput (Clarification Q2)
│           ├── sse_events.dart                      # MODIFIED — ContextRequestedEvent /
│           │                                        #   ContextRequestedTerminal (H1 fourth kind)
│           ├── ai_client_sdk.dart                   # MODIFIED — surface context_requested
│           │                                        #   terminal; each invoke() keeps a new
│           │                                        #   idempotency key (existing factory)
│           ├── context_resolver.dart                # CONSUMED (E3) — unchanged
│           ├── context_registration.dart            # CONSUMED (E3) — unchanged
│           ├── context_provider_port.dart           # CONSUMED (E3) — unchanged
│           ├── conversation_store.dart              # NEW — local transcript hold / resupply /
│           │                                        #   discard on close; no interpretation
│           └── conversation_loop.dart               # NEW — chat negotiation loop: submit leg,
│                                                    #   on context_requested resolve keys via
│                                                    #   Resolver (no capability id), append,
│                                                    #   new key; on completed append answer;
│                                                    #   cancel one leg only
├── test/
│   └── unit/
│       └── core/
│           └── ai/
│               ├── fakes.dart                       # EXTEND — conversational submit/SSE/
│               │                                    #   Resolver fakes/spies
│               ├── conversation_store_test.dart     # NEW — Flutter store + loop named tests
│               └── conversation_loop_test.dart      # NEW — negotiation / cancel / coverage
└── lib/features/ai/                                 # OPTIONAL test-only chrome (Clarification Q1)
    └── …                                            # only if a Flutter widget harness needs it;
                                                     # not a Freezes deliverable

# backend/ — UNCHANGED (Consumes E3 RPC under caller RLS; no rewrite)
```

**Structure Decision**: Journaling stays in C3's `src/journal/` — populate reserved columns and add
the A5-documented ordered conversation query helper; A5 follow-up index migration for
`idx_ai_request_conversation`; no conversation table or store. Conversation
store and negotiation loop live under `frontend/lib/core/ai/` beside E2/E3 (Clarification Q1).
Conversational submit fields are optional on existing `CapabilityInvokeInput` (Clarification Q2).
Pipeline `runGuard` (stage 6 conversational validate + stage 9 journal) parses
`conversation_id` / `turn_ordinal` / `transcript` from the submit body and passes them through
(H3-R5). Full-pipeline journaling tests also compose admission → `createRequestRow` →
fake provider → credit / R2 spies under the workers pool (Clarification Q3), matching the load
happy-path fixture style. No `backend/` path is
touched.

## Consumes Binding

| **Consumes** entry | Existing module / file bound to | How H3 binds to it |
| --- | --- | --- |
| **C3** — journal writer, post-response detail, get-request: `ai_request` row before work; §6.3 transitions; guard rejection → no row; one R2 envelope; `ai_attempt` / `usage_event` after response; get-request by reference | `ai-platform/src/journal/index.ts` (`createRequestRow`, `RequestRowInput.conversationId` / `turnOrdinal`, `journalTransition`, `recordTerminalState`, `writePostResponseDetail`, `getRequest`); frozen `specs/027-journal-writer-get-request/contracts/journal.md`; A5 columns in `ai-platform/migrations/20260731120000_platform_schema.sql` | H3 **populates** reserved nullable `conversation_id` / `turn_ordinal` on conversational legs (inputs already on `RequestRowInput`) and **adds** `listConversationLegs` as the one ordered query. It does **not** rewrite stage-9/15/16 lifecycle, one-envelope rule, get-request, or add a conversation table (FR-002–FR-007, FR-015). |
| **E2** — AI Client SDK: AAT acquire/cache, submit with idempotency key, SSE to terminal, cancel, no retry after terminal platform error, last request reference | `frontend/lib/core/ai/ai_client_sdk.dart`, `ports.dart` (`CapabilityInvokeInput`, `HttpsSubmitPort`), `sse_events.dart`, `taxonomy.dart`; plan `specs/036-ai-client-sdk/plan.md` | H3 **extends** `CapabilityInvokeInput` with optional `conversationId` / `turnOrdinal` / `transcript` (Clarification Q2) and surfaces H1's `context_requested` as a client terminal. Each leg calls `invoke()` so the SDK issues a **new** idempotency key. It does **not** rewrite transport, remint, or terminal-retry rules (FR-011, FR-014). |
| **E3** — Context Resolver registry: key list → payload; never receives/branches on capability id; screen-scoped cache | `frontend/lib/core/ai/context_resolver.dart` (`resolve` + H3 `resolveRequests`); `context_registration.dart`; `context_provider_port.dart`; frozen `specs/037-context-resolver-registry/contracts/context-resolver.md` (§2.4 arguments extension) | H3 **routes** full `{key, arguments}` entries through `resolveRequests` (key-list `resolve` remains); appends request + resolved payload to the transcript. It does **not** pass a capability id, add per-capability glue, or a second resolution path (FR-009, FR-010, FR-017). |
| **H1** — `interaction_mode: conversational` fields; `context_requested` terminal kind; `AwaitingContext` terminal/immutable; platform-owned `{key, arguments}` schema | `ai-platform/src/manifest/index.ts`; `ai-platform/src/adapter.ts` (`context_requested`); `ai-platform/src/journal/index.ts` (`AwaitingContext`); `ai-platform/src/context/context-request.ts`; frozen `specs/044-conversational-manifest-schema/contracts/*` | H3 **journals** legs that reach `AwaitingContext` and **drives** the client loop for `context_requested` / `completed`. It does **not** redefine manifest fields, the shared schema, or the fourth terminal kind (FR-007–FR-009). |

No Consumes entry lacks an implementation; satisfying H3 does not require rewriting C3/E2/E3/H1 frozen invariants beyond the reserved conversational extensions (stop condition 2 not triggered).

## Components Touched

| §4 component | What H3 changes | Behaviour added? |
| --- | --- | --- |
| **§4.3.11 Journal writer** | Populate client-supplied `conversation_id` / `turn_ordinal` on conversational `ai_request` rows; export one ordered conversation query helper; prove independent admit/journal/credit and `AwaitingContext` credit via pipeline integration | Yes — conversational column population + conversation read helper; lifecycle/envelope/get-request unchanged |
| **§4.1 Conversation store** | New client store + chat negotiation loop: hold/resupply/discard transcript; resolve keys via E3; append request/payload or completed answer; new idempotency key per leg; cancel one leg only | Yes — conversational capabilities only |
| **§4.1 AI Client SDK** | Optional conversational fields on `CapabilityInvokeInput`; client-side `context_requested` terminal | Yes — additive invoke/terminal surface; transport/remint/retry rules unchanged |

**Reason for touching more than one:** Delivery plan §3.8 row H3 Done when and this slice's Freezes jointly require (a) journaling of reserved grouping columns with one ordered conversation query and independent per-leg admit/credit, and (b) the client Conversation store / negotiation loop. Canonical cites §7.3 and §4.1 / §6.7 / §8.10 together. The SDK extension is the minimal wire for Clarification Q2 submit fields and for receiving H1's fourth terminal so the loop can run (FR-008, FR-009, FR-011). Splitting them would leave Done when and acceptance scenarios 1–12 incomplete. These surfaces cannot be tested apart for H3's Independent Test.

**Not touched:** §4.1 Context Resolver (consumed only — key extraction + existing `resolve`); §4.1 AI Feature Surfaces (E4; optional test chrome only); §4.3.5 / §4.3.6 / §4.3.9 (H2); backend §4.2.

## Files

| Path | Created / Modified | Traces to |
| --- | --- | --- |
| `ai-platform/src/journal/index.ts` | Modified — conversational column write (reject missing grouping); tenant-scoped `listConversationLegs(conversationId, installationId, db)`; `WHERE conversation_id = ? AND installation_id = ? ORDER BY turn_ordinal` | FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-015 |
| `ai-platform/src/pipeline/index.ts` | Modified — `runGuard` parses conversational wire fields and passes them to `validateContext` (stage 6) + `createRequestRow` (stage 9) | FR-001, FR-002, SC-001 |
| `ai-platform/migrations/20260805180000_h3_conversation_index.sql` | Created — A5 follow-up `idx_ai_request_conversation` | SC-002 |
| `ai-platform/test/conversational-journaling.test.ts` | Created — full pipeline integration (spy) journaling + coverage tests (Clarification Q3); `runGuard` wiring case | SC-001–SC-004, SC-007; journaling named tests + §3.10 coverage |
| `ai-platform/vitest.workers.config.ts` | Modified — include this slice's journaling test file | SC-001–SC-004 |
| `ai-platform/vitest.config.ts` | Modified — exclude workers-pool file from unit pool | SC-001–SC-004 |
| `frontend/lib/core/ai/ports.dart` | Modified — optional `conversationId`, `turnOrdinal`, `transcript` on `CapabilityInvokeInput` | FR-001, FR-005, FR-011, FR-012, FR-018 |
| `frontend/lib/core/ai/sse_events.dart` | Modified — `ContextRequestedEvent` / `ContextRequestedTerminal` | FR-008, FR-009 |
| `frontend/lib/core/ai/ai_client_sdk.dart` | Modified — surface `context_requested` terminal; preserve new idempotency key per `invoke()` | FR-008, FR-009, FR-011, FR-014 |
| `frontend/lib/core/ai/conversation_store.dart` | Created — transcript hold / resupply / discard; no interpretation / key choice | FR-012, FR-013, FR-016 |
| `frontend/lib/core/ai/conversation_loop.dart` | Created — negotiation loop: Resolver path, append, new key per leg, cancel one leg | FR-008, FR-009, FR-010, FR-011, FR-014, FR-017 |
| `frontend/test/unit/core/ai/fakes.dart` | Modified — conversational fakes/spies | test support for FR-008–FR-014 |
| `frontend/test/unit/core/ai/conversation_store_test.dart` | Created | SC-005, SC-006; store named tests + coverage |
| `frontend/test/unit/core/ai/conversation_loop_test.dart` | Created | SC-005, SC-006; loop / cancel / coverage |
| `specs/046-conversational-journaling/contracts/conversational-journaling.md` | Created | Freezes (column write, ordered query, independent admit/credit, no conversation entity/state) |
| `specs/046-conversational-journaling/quickstart.md` | Created during Documentation task after verification | Documentation mandate |

No Consumes module is rewritten beyond the reserved extensions. Conversational grouping index is an
A5 follow-up one-statement migration (H3-R4). No `wrangler.toml` binding change, no `backend/` files.
Conversation store Freezes are client behavioural (E2 pattern) — later slices bind to
`frontend/lib/core/ai/conversation_*.dart`, not to a separate store wire contract.

## Test Layout

Layer: **Integration (spy) + Flutter** (delivery plan §3.11.7 row H3). Journaling maps to §13.5 **Pipeline tests** (fake provider; deterministic; admission/credit/R2 spies). Client maps to the Flutter unit/integration suite under `frontend/test/unit/core/ai/` (same placement as E2/E3 client cases; Architecture guard inherits R-12 via existing E1 coverage of `lib/core/ai/`).

| Spec Test plan name | Layer (§13.5) | File | Asserts |
| --- | --- | --- | --- |
| `conversation_id_and_turn_ordinal_written_per_leg` | Pipeline (integration spy) | `conversational-journaling.test.ts` | FR-001, FR-002 / SC-001 |
| `one_indexed_query_returns_whole_conversation_ordered` | Pipeline (integration) | `conversational-journaling.test.ts` | FR-003 / SC-002 |
| `each_leg_admitted_and_credited_independently` | Pipeline (integration spy) | `conversational-journaling.test.ts` | FR-006 / SC-003 |
| `context_requested_leg_credited_with_actual_usage` | Pipeline (integration) | `conversational-journaling.test.ts` | FR-007 / SC-003 |
| `no_conversation_table_and_no_per_request_state_object` | Pipeline (integration spy) | `conversational-journaling.test.ts` | FR-004, FR-015 / SC-004 |
| `transcript_held_locally_and_resupplied_per_leg` | Flutter | `conversation_store_test.dart` | FR-005, FR-012 / SC-005 |
| `requested_keys_resolved_through_existing_resolver_no_capability_branching` | Flutter | `conversation_loop_test.dart` | FR-009, FR-010 / SC-005 |
| `each_leg_uses_new_idempotency_key` | Flutter | `conversation_loop_test.dart` | FR-011 / SC-005 |
| `transcript_discarded_on_close` | Flutter | `conversation_store_test.dart` | FR-012 / SC-005 |
| `closing_one_leg_stream_cancels_only_that_leg` | Flutter | `conversation_loop_test.dart` | FR-014 / SC-006 |
| `conversation_survives_cancelled_leg` | Flutter | `conversation_loop_test.dart` | FR-014 / SC-006 |

**Coverage additions (§3.10):**

| Named test | Layer | File | Asserts |
| --- | --- | --- | --- |
| `client_never_interprets_message_or_chooses_keys` | Flutter (spy) | `conversation_store_test.dart` | FR-013 / §4.1; §8.10 |
| `append_completed_answer_to_transcript` | Flutter | `conversation_loop_test.dart` | FR-008 / §6.7.2 |
| `append_context_request_and_resolved_payload_to_transcript` | Flutter | `conversation_loop_test.dart` | FR-009 / §6.7.2 |
| `authorization_is_users_own_rls_not_reimplemented` | Flutter / integration | `conversation_loop_test.dart` | FR-017 / §8.10 |
| `platform_held_no_state_between_legs` | Pipeline (integration spy) | `conversational-journaling.test.ts` | FR-005, FR-015 / §8.10 |
| `no_second_r2_object_and_no_second_quota_do_round_trip_from_h3` | Pipeline (integration spy) | `conversational-journaling.test.ts` | FR-015 / §7.5; §13.6 |
| `no_prompt_provider_or_model_in_conversation_store` | Flutter / Architecture guard | `conversation_store_test.dart` (+ E1 on new paths) | FR-016 / R-12 |
| `single_shot_unaffected_by_h3` | Pipeline / Flutter | `conversational-journaling.test.ts` + `conversation_store_test.dart` | FR-018 / §6.7 preamble |

H3 emits no new §5.4 taxonomy codes — Edge Cases: none new (stop condition 3 not triggered; every named test places).

## Sequencing

1. **`contracts/conversational-journaling.md`** — freeze column-write + ordered query + independent admit/credit / no conversation entity so later support/evals bind to an artifact (Freezes wire/query shapes).
2. **`ai-platform/src/journal/index.ts`** — confirm conversational `createRequestRow` writes client-supplied fields; add `listConversationLegs` (FR-002, FR-003).
3. **`ai-platform/test/conversational-journaling.test.ts` + vitest workers include/exclude** — full pipeline integration (Clarification Q3): multi-leg admit → journal with conversation fields → fake provider → credit/R2 spies; ordered query; `context_requested` credit; no conversation table/state; I/O budget spies; `single_shot` null columns — tests alongside or before step 2 branches.
4. **`frontend/lib/core/ai/ports.dart` + `sse_events.dart` + `ai_client_sdk.dart`** — optional invoke fields (Clarification Q2); `context_requested` client terminal (FR-008, FR-011).
5. **`frontend/lib/core/ai/conversation_store.dart`** — hold / resupply / discard; no interpretation (FR-012, FR-013, FR-016).
6. **`frontend/test/unit/core/ai/conversation_store_test.dart` + fakes** — store named tests + coverage (`client_never_interprets…`, `no_prompt…`, `single_shot_unaffected` client half) alongside step 5.
7. **`frontend/lib/core/ai/conversation_loop.dart`** — negotiation loop using SDK + existing Resolver `resolve(keys)` with no capability id; append; cancel one leg (FR-008–FR-011, FR-014, FR-017).
8. **`frontend/test/unit/core/ai/conversation_loop_test.dart`** — loop / cancel / append / RLS-empty / new-key tests alongside step 7.
9. **Run** slice-only `npx vitest run test/conversational-journaling.test.ts --config vitest.workers.config.ts` and `flutter test` on this slice's Flutter files — all green; prior suites remain green (delivery plan §3.10).
10. **`quickstart.md`** — fill from the AI platform quickstart template (slice-only files and commands) during the Documentation task after verification.

Tests land alongside or before their implementation branches; no test is written after its implementation. `quickstart.md` is named here and filled after the suite is green.

## Complexity Tracking

> Not filled — no Constitution Check violation requires justification. Multi-component touch is
> recorded under Components Touched with an explicit reason (stop condition 5 satisfied by reason,
> not by Complexity Tracking).
