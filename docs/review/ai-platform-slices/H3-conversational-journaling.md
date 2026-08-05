# Slice Review: H3 — Conversational journaling and client chat surface

**Reviewed against:** `docs/architecture/17-ai-platform.md` §7.3, §6.7.1, §8.10, §4.1, §6.7,
amendment A14 (source of truth); `specs/046-conversational-journaling/` (spec, plan, tasks,
contracts, quickstart).
**Implementation reviewed:** `ai-platform/src/journal/index.ts`,
`ai-platform/test/conversational-journaling.test.ts`,
`ai-platform/migrations/20260731120000_platform_schema.sql` (read-only, A5-owned),
`frontend/lib/core/ai/conversation_store.dart`, `frontend/lib/core/ai/conversation_loop.dart`,
`frontend/lib/core/ai/ports.dart`, `frontend/lib/core/ai/sse_events.dart`,
`frontend/lib/core/ai/ai_client_sdk.dart`, `frontend/lib/core/ai/context_resolver.dart`,
`frontend/test/unit/core/ai/conversation_store_test.dart`,
`frontend/test/unit/core/ai/conversation_loop_test.dart`.
**Method:** Static review only; no build, no test execution.

## 1. Executive Summary

H3 delivers the journal half of its contract well: `createRequestRow` writes client-supplied
`conversation_id` / `turn_ordinal` on conversational legs and forces `NULL` on `single_shot`
(`journal/index.ts:181-186`), `listConversationLegs` implements the frozen one-query ordered read
(`journal/index.ts:506-521`), no conversation table or per-request state object exists, and the
workers-pool suite proves per-leg admit/credit including `AwaitingContext` credit with actual
usage. The Flutter store and loop cover the named client cases: hold/resupply/discard, Resolver
resolution with no capability id, new idempotency key per leg, per-leg cancel isolation, and
conversation survival.

One critical issue was found: **the negotiation loop never submits the continuation leg after
`context_requested`** — it resolves and appends, then returns the terminal to the caller, so the
§8.10 flow cannot complete and the done-when "submits the next leg with a new idempotency key" is
unmet. The notable highs are: the store's ordinal scheme violates the §6.7.1 wire rule (transcript
turn ordinals are not strictly less than the leg's own `turn_ordinal`, so H2's validator would
reject every leg this client produces), the "one **indexed** query" has no index on
`conversation_id` anywhere in the schema, and no production code path parses
`conversation_id` / `turn_ordinal` / `transcript` from the submit body — the journaling done-when
is proven only in test composition. All eleven required named tests and all eight §3.10 coverage
additions are present; several assertions are weaker than their names claim.

## 2. Critical Issues

- **[Critical] The negotiation loop does not loop: no continuation leg is submitted after
  `context_requested`** — `frontend/lib/core/ai/conversation_loop.dart:82-96`
  (`_handleTerminal`, `ContextRequestedTerminal` branch) appends the `context_requested` turn,
  resolves the keys, appends `context_resolved`, and then simply returns; `submitLeg`
  (`conversation_loop.dart:34-57`) returns the `ContextRequestedTerminal` to the caller. The only
  way to continue is another `submitLeg(userMessage)`, which fabricates a spurious `user` turn
  (`conversation_store.dart:28-43`). §8.10 shows the client submitting leg 2 immediately after
  resolving ("append request + resolved payload to transcript → leg 2: submit"), and the slice's
  own done-when requires "appends the request and payload, submits the next leg with a new
  idempotency key" (spec FR-009; acceptance scenario 9–10). As implemented, a turn that ends in
  `context_requested` never receives its answer: the resolved context sits in the local transcript
  and is never submitted. The test suite enshrines the gap —
  `requested_keys_resolved_through_existing_resolver_no_capability_branching`
  (`conversation_loop_test.dart:12-47`) scripts a second submit step
  (`completedStream(requestReference: 'req-leg-2')`) that is never consumed, and no test asserts a
  second submit occurs.

## 3. Bugs

- **[High] Transcript turn ordinals violate the §6.7.1 wire rule on every leg** —
  `conversation_store.dart:13-14` keeps two independent counters (`_nextLegOrdinal`,
  `_nextTranscriptOrdinal`), and `prepareLegSubmit` (`conversation_store.dart:28-43`) appends the
  current user message to the transcript *before* returning the leg ordinal. Leg 1 therefore
  submits `turn_ordinal: 1` with a transcript whose only turn has `turn_ordinal: 1` — not
  "strictly less than the leg's own `turn_ordinal`" as §6.7.1 requires. It gets worse as the
  conversation grows: after one model answer, leg 2 carries transcript ordinals 1, 2, 3 against a
  leg ordinal of 2. Every transcript this client produces is a malformed turn set under
  §6.7.1 ("a `turn_ordinal` that does not respect the ordering rule is … rejected … with
  `context_invalid`"), so once H2's validator lands, every conversational leg from this client
  fails. The store test enshrines the violation rather than catching it
  (`conversation_store_test.dart:10-21` asserts `leg1.turnOrdinal == 1` with a one-turn
  transcript). §8.10's leg 1 has an *empty* transcript with the message in the intent field; this
  client puts the current message in the transcript instead.
- **[Medium] The typed message never reaches the intent field** —
  `conversation_loop.dart:41-49` submits `_baseInput.intent` verbatim on every leg; the clinician's
  actual message travels only inside the transcript. A14 and §8.10 are explicit that the chat
  capability's "user intent field is the literal typed message" (§2.5; §8.10 leg 1:
  `intent = the message`). A fixed intent for all legs also means the journaled request and the R2
  envelope do not record what the user actually asked as the intent, weakening the §8.10 "each leg
  is independently accountable" audit story.
- **[Medium] Requested-key arguments are dropped before resolution** —
  `conversation_loop.dart:84-87` maps each `{key, arguments}` entry to `entry['key']` and calls
  `ContextResolver.resolve(List<String> keys)` (`context_resolver.dart:40`), which has no arguments
  channel. §6.7.2 and §8.10 specify context keys "with their arguments" (the §8.10 example resolves
  data *for patient "Ahmed"* — an argument). The plan's Consumes Binding ("keys extracted from the
  H1 `{key, arguments}` list") blesses the drop, but architecture is the source of truth: a
  resolver that needs an argument (patient id, date range) cannot receive one. Report as a
  documentation/architecture mismatch; either E3's contract must grow an arguments channel or the
  architecture sections need amendment.
- **[Low] A cancelled or failed leg leaves a dangling `user` turn in the transcript** —
  `prepareLegSubmit` appends the user turn before submit (`conversation_store.dart:31-36`), and
  `_handleTerminal` does nothing for `FailedTerminal` / `CancelledTerminal`
  (`conversation_loop.dart:93-95`). The next leg resupplies a transcript containing a user message
  the platform may never have journaled (cancel pre-acceptance) or never answered. §6.7.4 only
  requires the conversation to survive; silently resubmitting an unanswered turn is a behavioural
  choice that should be deliberate (and tested), not accidental.
- **[Low] Resolver failure is journaled into the transcript as an empty resolution** —
  `conversation_loop.dart:90-92` appends `context_resolved` with an empty payload on
  `ContextResolveFailure`, making a client-side resolution failure indistinguishable from an
  RLS denial ("payloads — or nothing", §8.10). The platform will treat the keys as
  resolved-to-nothing and answer anyway, rather than the leg failing visibly.
- **[Low] Conversational legs missing grouping fields silently write `NULL`** —
  `journal/index.ts:183-186` writes `input.conversationId ?? null` for non-`single_shot` requests.
  A conversational leg submitted without `conversation_id` / `turn_ordinal` is journaled as an
  ungrouped orphan rather than rejected, so a whole-conversation read can silently lose legs.
  §6.7.1 makes the fields client-supplied per leg; whether absence is `context_invalid` is H2's
  call, but the journal defaulting to `NULL` forecloses nothing and records nothing.

## 4. Architectural Deviations

- **[High] "One indexed query" is not indexed** — §7.3 states `conversation_id` and
  `turn_ordinal` "group and order the legs so that support can read a whole conversation with one
  **indexed** query", and the required test is named
  `one_indexed_query_returns_whole_conversation_ordered`. The only index on `ai_request` in the
  schema is `idx_ai_request_request_reference`
  (`migrations/20260731120000_platform_schema.sql:84`); `conversation_id` (line 79) has none, so
  `listConversationLegs` (`journal/index.ts:506-521`) is a full scan of the platform's dominant
  table. H3 was correctly barred from adding a migration (columns reserved in A5), which means the
  index should have been reserved alongside the columns in A5 — a cross-slice gap to close with a
  one-statement migration, not a code change. The H3 test never asserts index existence, so the
  regression is invisible to the suite (see §5).
- **[High] No production path wires the conversational fields from the wire to the journal** —
  nothing under `ai-platform/src/` outside `journal/index.ts` references `conversationId`,
  `turnOrdinal`, or `transcript` (verified by search): `adapter.ts` (the `/v1/requests` handler
  routed from `worker.ts:108-110`) never parses them from the submit body, and no module in `src/`
  calls `createRequestRow` at all. The done-when "`conversation_id` and `turn_ordinal` are written
  per leg" is therefore proven only in the test's manual composition
  (`conversational-journaling.test.ts:430-520`), not on any request path a client can reach. If
  pipeline orchestration is deliberately a later slice, the H3 spec/quickstart overclaim ("Every
  conversational leg's `ai_request` row carries the submitted `conversation_id`", SC-001); if it
  is H3's, the wiring is missing functionality.
- **[Low] `listConversationLegs` is not tenant-scoped** — `journal/index.ts:512-517` filters by
  `conversation_id` alone. The id is client-supplied with no uniqueness or tenancy constraint, so
  colliding ids across installations would merge two clinics' legs into one "conversation" for
  support/evals readers. The sibling read path (`getRequest`) is installation-scoped; this helper
  should take the installation id (or document why support reads are exempt).
- **[Low] Per-leg SDK reconstruction defeats E2's AAT cache** —
  `conversation_loop.dart:64-73` builds a fresh `AiClientSdk` per leg whenever an
  `idempotencyKeyFactory` is supplied, discarding the cached AAT (`ai_client_sdk.dart:30, 71-80`)
  and `lastRequestReference` — an extra mint per leg. It is also unnecessary: `invoke()` already
  calls the factory once per invocation (`ai_client_sdk.dart:38`), so the reused SDK yields a new
  key per leg without reconstruction. Dead-weight complexity today (only tests supply a factory),
  a performance regression if ever used in production.
- **Verified non-deviations:** no `conversation` table or entity
  (`conversational-journaling.test.ts:741-771` asserts the schema); no new D1 migration from H3;
  no new pipeline stage, store, or stateful component; `single_shot` rows forced to `NULL`
  grouping columns (`journal/index.ts:181-186`, tested at
  `conversational-journaling.test.ts:861-887`); one R2 envelope per leg preserved
  (`conversational-journaling.test.ts:817-859`); no new §5.4 taxonomy code; Resolver invoked with
  a key list and no capability id (`conversation_loop.dart:84-87`; E3 contract intact); no
  prompt/provider/model identifiers in the new client files (architecture-guard test,
  `conversation_store_test.dart:47-58`).

## 5. Missing or Weak Tests

**Required cases present (delivery plan §3.11.7 floor):** all five journaling cases —
`conversation_id_and_turn_ordinal_written_per_leg`,
`one_indexed_query_returns_whole_conversation_ordered`,
`each_leg_admitted_and_credited_independently`,
`context_requested_leg_credited_with_actual_usage`,
`no_conversation_table_and_no_per_request_state_object` — and all six client cases —
`transcript_held_locally_and_resupplied_per_leg`,
`requested_keys_resolved_through_existing_resolver_no_capability_branching`,
`each_leg_uses_new_idempotency_key`, `transcript_discarded_on_close`,
`closing_one_leg_stream_cancels_only_that_leg`, `conversation_survives_cancelled_leg` — exist as
named. All eight §3.10 coverage additions also exist (`client_never_interprets_message_or_chooses_keys`,
`append_completed_answer_to_transcript`, `append_context_request_and_resolved_payload_to_transcript`,
`authorization_is_users_own_rls_not_reimplemented`, `platform_held_no_state_between_legs`,
`no_second_r2_object_and_no_second_quota_do_round_trip_from_h3`,
`no_prompt_provider_or_model_in_conversation_store`, `single_shot_unaffected_by_h3` — both halves).

**Required cases missing:** none by name. The behavioural shortfalls are inside present tests:

- **[High] No test that the loop submits the continuation leg after `context_requested`** —
  because the implementation does not (§2). The done-when chain "resolve → append → submit next
  leg with a new idempotency key" has no test for its final step; the scripted second submit in
  `conversation_loop_test.dart:17-20` is never consumed and would not fail if removed.
- **[High] No test asserts the §6.7.1 transcript ordering rule** — no case checks that every
  transcript turn ordinal is strictly less than the leg's `turn_ordinal` (or strictly increasing,
  duplicate-free). The existing store test asserts the violating shape
  (`conversation_store_test.dart:10-21`), so the bug in §3 is locked in as expected behaviour.
- **[Medium] The "indexed" claim is never verified** —
  `one_indexed_query_returns_whole_conversation_ordered`
  (`conversational-journaling.test.ts:599-648`) asserts ordering only; no assertion (e.g. against
  `sqlite_master` indexes or `EXPLAIN QUERY PLAN`) would fail if the `conversation_id` index is
  absent — and it is absent (§4).
- **[Medium] The I/O-budget tests cannot catch a second Quota DO round trip** —
  `no_second_r2_object_and_no_second_quota_do_round_trip_from_h3` asserts
  `spies.do.fetchCount()` with `toBeGreaterThanOrEqual(1)` per leg
  (`conversational-journaling.test.ts:841-858`), and
  `each_leg_admitted_and_credited_independently` uses `toBeGreaterThanOrEqual(3)` for three legs
  (line 704). A regression adding two or five DO trips per leg still passes; the prohibition is
  an upper bound and must be asserted as one (`toBeLessThanOrEqual` against the known per-leg
  budget, as the R2 half already does with exact counts).
- **[Medium] Resupply is asserted at the store boundary, not the wire** —
  `transcript_held_locally_and_resupplied_per_leg` (`conversation_store_test.dart:8-22`) checks
  the snapshot returned by `prepareLegSubmit`; no loop-level test asserts that the
  `CapabilityInvokeInput` received by the submit port on leg *n* carries the transcript
  accumulated through leg *n−1* (including the resolved context). The store-to-SDK handoff
  (`conversation_loop.dart:48`) is untested.
- **[Low] No test for the intent field carrying the typed message** — consistent with the bug in
  §3; §8.10's `intent = the message` has no behavioural assertion anywhere in the slice.
- **[Low] `platform_held_no_state_between_legs` proves only D1-row shape** —
  `conversational-journaling.test.ts:773-815` reads journal rows between legs; it cannot observe
  a per-request state object (e.g. a new DO binding or module-level map) introduced elsewhere.
  Pro-forma coverage of FR-005/FR-015, similar in kind to H1's export-name-regex prohibitions.

## 6. Recommended Improvements

1. **[Critical] Make the loop continue after `context_requested`**: after appending
   `context_requested` + `context_resolved`, submit the continuation leg automatically (new
   idempotency key, resupplied transcript, no fabricated `user` turn), looping until `completed`
   or a failure terminal — and add the test that asserts the second submit occurs with the
   resolved payload on the wire (§6.7.2; §8.10; FR-009).
2. **[High] Fix the ordinal scheme in `ConversationStore`**: either keep the current user message
   out of the transcript (put it in `intent`, matching §8.10) and number transcript turns so every
   ordinal is strictly less than the leg's `turn_ordinal`, or derive leg ordinals from the
   transcript counter (`leg ordinal = last transcript ordinal + 1`). Add a wire-rule conformance
   test: strictly increasing, duplicate-free, all less than the leg ordinal (§6.7.1).
3. **[High] Add the missing `conversation_id` index** via a one-statement migration
   (`CREATE INDEX idx_ai_request_conversation ON ai_request (conversation_id, turn_ordinal)`),
   recorded as an A5 follow-up since H3 may not migrate; extend the ordered-query test to assert
   index existence (§7.3).
4. **[High] Wire the fields on the request path or narrow the claim**: parse `conversation_id`,
   `turn_ordinal`, and `transcript` from the submit body in the adapter/pipeline and pass them to
   `createRequestRow`, or explicitly document in the spec/quickstart that SC-001 is proven at
   module-composition level pending the pipeline slice.
5. **[Medium] Pass context-request arguments through resolution**: extend the E3 Resolver contract
   (or the loop's extraction) so `{key, arguments}` reaches the resolver function, per §6.7.2 /
   §8.10; reconcile the plan's keys-only wording with the architecture.
6. **[Medium] Assert DO round trips as an upper bound** in the two I/O-budget tests (exact or
   `≤` per-leg counts), mirroring the exact R2 assertions (delivery plan §6.4; §7.5).
7. **[Low] Scope `listConversationLegs` by installation** (parameter + `AND installation_id = ?`),
   matching `getRequest`'s tenancy posture.
8. **[Low] Delete the per-leg SDK reconstruction** in `_sdkForLeg` — pass the factory to the one
   SDK at construction; `invoke()` already mints a fresh key per call.
9. **[Low] Decide and test the dangling-turn policy** for cancelled/failed legs (keep-and-resubmit
   vs. roll back the unanswered `user` turn), and distinguish resolver failure from RLS-empty in
   what is appended (or fail the leg visibly instead of appending an empty `context_resolved`).

---

## 7. Review Resolution

### 7.1 Stage grouping

| Stage | Review items covered | Files / logic |
| --- | --- | --- |
| **H3-R1 — Negotiation loop continues** | Critical #1; Missing/Weak Tests #1; Rec #1 | `frontend/lib/core/ai/conversation_loop.dart`; `conversation_loop_test.dart` |
| **H3-R2 — Ordinals, intent, dangling-turn rollback** | Bugs #1, #2, #4; Missing/Weak Tests #2, #5, #6; Rec #2, #9 (dangling) | `conversation_store.dart`; `conversation_loop.dart`; store/loop tests |
| **H3-R3 — Resolver arguments + failure visibility** | Bugs #3, #5; Rec #5, #9 (resolver failure) | `context_resolver.dart`; `context_registration.dart`; E3 contract §2.4; loop + resolver tests |
| **H3-R4 — Conversation index + reject NULL grouping + tenant scope** | Bugs #6; Arch Deviations #1, #3; Missing/Weak Tests #3; Rec #3, #7 | `migrations/20260805180000_h3_conversation_index.sql`; `journal/index.ts`; journaling tests |
| **H3-R5 — Wire conversational fields on request path** | Arch Deviation #2; Rec #4 | `pipeline/index.ts` (`runGuard` parse → validate → `createRequestRow`); Spec Kit SC-001 |
| **H3-R6 — DO budget upper bounds + no-state strengthen + SDK** | Arch Deviation #4; Missing/Weak Tests #4, #7; Rec #6, #8 | `conversational-journaling.test.ts` DO exact budgets / no-state probes; SDK reconstruction already removed |

Every numbered review item appears in exactly one stage. No escalations — arguments channel is an allowed E3 contract extension; index is an A5 follow-up migration (no architecture amend).

### 7.2 Test cases created first

- **H3-R1:** `continuation_leg_submitted_after_context_requested_with_resolved_payload` — second submit carries resolved context on the wire; existing context_requested cases now expect `submitCallCount == 2`.
- **H3-R2:** `transcript_wire_ordinals_strictly_less_than_leg_ordinal`; `prepare_leg_submit_intent_is_typed_message_empty_transcript_on_leg_one`; `intent_field_carries_typed_message_not_base_intent`; `wire_resupply_carries_prior_transcript_including_resolved_context`; `failed_leg_does_not_leave_dangling_user_turn` / store rollback case.
- **H3-R3:** `loop_passes_key_and_arguments_to_resolver`; `resolve_requests_passes_arguments_to_registration`; `context_resolve_failure_does_not_append_or_continue`; RLS-empty remains success with empty payload.
- **H3-R4:** index existence via `sqlite_master` in `one_indexed_query_…`; reject-missing grouping fields; tenant-scoped `listConversationLegs`.
- **H3-R5:** `runGuard` conversational body writes `conversation_id` / `turn_ordinal` on the `ai_request` row.
- **H3-R6:** DO fetches asserted exact (`2` per leg / `6` for three legs); `platform_held_no_state_between_legs` strengthened with DO/module probes.

### 7.3 Fix implemented

- **Loop:** after successful resolve, auto-submits continuation (`prepareContinuationSubmit`) until `completed` or fail/cancel; no fabricated user turn.
- **Store:** intent = typed message; prior-only transcript on submit; leg ordinal = last transcript ordinal + 1; user turn committed only on success; cancel/fail discard pending.
- **Resolver:** `resolveRequests({key, arguments})` extension; key-list `resolve` retained; `ContextResolveFailure` → visible `FailedTerminal` (no empty `context_resolved`); RLS-empty stays success.
- **Journal:** conversational legs reject missing grouping (`context_invalid`); `listConversationLegs(conversationId, installationId, db)`; A5 follow-up `idx_ai_request_conversation`.
- **Pipeline:** `runGuard` extracts `conversation_id` / `turn_ordinal` / `transcript` from body, passes H2 conversational validate options, journals grouping columns at stage 9.
- **I/O budgets:** exact DO per-leg counts; SDK per-leg reconstruction already absent (AAT cache preserved across legs).
- **Spec Kit:** H3 contracts/spec/plan/quickstart/tasks + E3 contract §2.4 updated. Architecture and delivery plan untouched.

### 7.4 Verification

Full `ai-platform` `npm test`: verify-manifests **2 files / 4 tests**; node Vitest **41 files / 634 tests**; workers Vitest **19 files / 270 tests** — all passed.

Flutter (H3 client): `conversation_store_test` + `conversation_loop_test` + `context_resolver_test` — **21+** named cases including new continuation/ordinal/intent/arguments/failure cases — all passed.
