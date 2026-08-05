# Slice Review: H1 — Conversational manifest fields and context-request schema

**Reviewed against:** `docs/architecture/17-ai-platform.md` §5.1, §5.4, §5.5, §5.7, §6.3, §6.7.2, §6.7.4, amendment A14 (source of truth); `specs/044-conversational-manifest-schema/` (spec, plan, tasks, contracts).
**Implementation reviewed:** `ai-platform/src/manifest/index.ts`, `ai-platform/src/context/context-request.ts`, `ai-platform/src/adapter.ts`, `ai-platform/src/journal/index.ts`, `ai-platform/src/errors.ts`, plus the four H1 test files and `ai-platform/test/helpers/adapter-stub.ts`.
**Method:** Static review only; no build, no test execution.

## 1. Executive Summary

H1 is a faithful, well-scoped implementation of the A14 contract freeze. The core requirements are correctly implemented and tested: a `conversational` manifest loads with all four extras and fails naming each omission; conversational-only fields are rejected on `single_shot`; the permitted key set is gated against the A5 published vocabulary; in-place `interaction_mode` changes fail the build via the published-registry hash check; the shared platform-owned `{key, arguments}` schema accepts conforming and rejects each named malformed form; `context_requested` is a fourth terminal SSE kind gated on `interactionMode` and is absent from (and refused by) the §5.4 taxonomy; `AwaitingContext` is terminal and immutable in the journal. The no-rework rule is respected for A4 (ten field groups, `single_shot` default, loader contract intact) and A6 (three existing terminal kinds and the one-terminal-event invariant untouched).

No critical issues were found. The notable findings are: the three conversational numeric fields are validated for **presence only** (no type/range check), the conversational-only reachability guard for `AwaitingContext` exists as an exported helper but is **never called** in the write path, `errors.ts` was modified despite the plan declaring it unchanged (plan-vs-code mismatch plus a throw inside an error-path builder), and two of the required integration/coverage tests are weaker than their names claim (a circular stub-gated test, and export-name-regex prohibition tests).

## 2. Critical Issues

None found.

## 3. Bugs

- **[Medium] Conversational Interaction fields are checked for presence only, never for type or range** — `ai-platform/src/manifest/index.ts:337-344` (`assertConversationalInteractionFields`) verifies `maxHistoryTurns`, `maxContextRoundsPerTurn`, and `transcriptSizeLimit` exist, but a manifest with `maxHistoryTurns: "ten"`, `-3`, `0`, or `1.5` loads successfully. §5.1 defines these as numeric limits consumed by the context validator and prompt composer, and spec acceptance scenario 1 requires the fields to be "present and well-formed". The loader already has the pattern for this — `assertEconomicsTypes` (`manifest/index.ts:291-297`) type-checks every Economics field — but it was not applied to the H1 fields. A malformed numeric limit would surface only at H2 runtime budget counting, far from the build-time failure the architecture intends.
- **[Low] `context_requested` terminal event is emitted without validating its payload against the shared schema** — `ai-platform/src/adapter.ts:130-138` pushes `payload?.context_request ?? []` verbatim; `validateContextRequest` is never called on the emission path. The frozen contract (`contracts/context-requested-terminal.md` §1) states the payload is "a conforming context request per `context-request-schema.md`" (§6.7.2, §5.5 rule 4). A caller passing a malformed payload — or nothing — streams a non-conforming (or empty) context request to the client. If payload validation is deliberately H2's wiring, the handoff should be explicit; as frozen, the contract already asserts conformance.
- **[Low] `buildErrorBody` now throws on the literal string `"context_requested"`** — `ai-platform/src/errors.ts:202-204`. This changes A2-frozen behavior for unknown-code input (previously any unknown code classified to `internal_error`, matching the §5.7 "unknown codes as `internal_error`" spirit) and introduces a throw inside the platform's error-body builder — a resilience hazard if ever reached from a live error-handling path. The intent (refusing `context_requested` as an error code) is correct; a throw in the error path is the wrong mechanism. See also the plan mismatch in §4.

## 4. Architectural Deviations

- **[Medium] Conversational-only reachability of `AwaitingContext` is not enforced in the journal write path** — §6.3 and FR-010 require `AwaitingContext` to be reachable only for `conversational` capabilities. The enforcement helper `canReachAwaitingContext` (`ai-platform/src/journal/index.ts:152-156`) is exported but **never called anywhere in `src/`** (verified by search; only the test imports it). `journalTransition` and `recordTerminalState` (`journal/index.ts:233-289`) take no interaction mode and apply no mode gate, so a `single_shot` request row can be written into `AwaitingContext` without obstruction. The rule currently exists only as dead code plus a pure-function test.
- **[Medium] Plan/documentation mismatch: `errors.ts` was modified though the plan froze it as unchanged** — `specs/044-conversational-manifest-schema/plan.md` (Files table: "`errors.ts` is not modified"; Consumes Binding: "CONSUMED (A2) — unchanged"; "No Consumes module is rewritten") contradicts the actual `errors.ts:202-204` guard added by H1. The change is small and arguably an extension rather than a rewrite, but the Speckit record misstates what happened to an A2-frozen module — a documentation issue under the source-of-truth rule, and it weakens the "consumes, never rewrites" audit trail the delivery plan §2.3 depends on.
- **[Low] `isJournalTransitionAllowed` does not encode the §6.3 graph** — `journal/index.ts:142-150` returns `false` only when the source state is terminal; every non-terminal source may transition to *any* target (e.g. `Accepted → Completed`, `Composing → AwaitingContext`). The function name and the test (`awaiting-context.test.ts:43-48`) imply graph validation, but only terminal immutability is actually implemented. This is consistent with C3's minimal design (the SQL `TERMINAL_IMMUTABLE_WHERE` is the real guard), so it is a naming/abstraction weakness rather than a behavioral deviation — but H1's own test asserts a mode-blind `Validating → AwaitingContext` transition, which reads as endorsing reachability the architecture restricts to conversational legs.
- **Verified non-deviations (no-rework rule holds):** the ten §5.1 field groups, the omitted-mode `single_shot` default, and A4's presence/absence rejection are intact (`manifest/index.ts:6-76, 366-374`); the permitted-key-set form replaces the Context-requirements group only under `conversational` (`manifest/index.ts:453-462`); A6's three terminal kinds and one-terminal invariant are extended, not rewritten (`adapter.ts:13-18, 87-97`); no new §5.4 code was added (`errors.ts:1-19` — `conversation_budget_exhausted` predates H1); no new store, table, or pipeline stage was introduced.

## 5. Missing or Weak Tests

Required-case coverage is otherwise complete: all eight manifest cases, the shared-schema accept plus four malformed-form rejects, taxonomy absence, `AwaitingContext` terminality, and both stream cases exist as named in `specs/044-conversational-manifest-schema/spec.md` Test plan.

- **[Medium] No test for malformed *values* of the conversational numeric fields** — wrong type, negative, zero, or non-integer `maxHistoryTurns` / `maxContextRoundsPerTurn` / `transcriptSizeLimit` are neither rejected by the loader (Bug, §3) nor tested. Under the §3.10 every-branch rule and spec scenario 1's "well-formed" wording, one rejection case per malformed value class is missing.
- **[Medium] `single_shot_never_emits_context_requested` is partially circular** — `ai-platform/test/context-requested-terminal.test.ts:100-123` drives `createModeGatedStubEventSource("single_shot", "context_requested", …)`, but the mode gate being exercised lives **inside the test helper**: the stub silently downgrades the requested `context_requested` to `completed` (`test/helpers/adapter-stub.ts:67-71` and `81-83`). The integration case therefore proves the stub's fallback, not that a production path cannot emit the fourth kind. The direct `pushTerminalEvent`-throws case (`context-requested-terminal.test.ts:124-145`) carries the real assertion; the stream-level case adds little beyond it.
- **[Low] The two §3.10 prohibition tests assert export-name regexes, not behavior** — `no_new_pipeline_stage_from_conversational_mode` and `no_per_request_server_state_from_h1` (`test/context-request.test.ts:70-99`) pass as long as no export of one module matches `/stage/`, `/handler/`, `/durableobject/`, etc. An actual new pipeline stage or session store added in any other file would not fail these tests. They are pro-forma coverage of FR-011 / §6.7.4.
- **[Low] Omitted-`interactionMode` default combined with conversational fields is untested** — FR-005 / §5.1: when `interactionMode` is omitted it defaults to `single_shot`, and conversational-only fields must then be rejected. `conversational_fields_rejected_on_single_shot` (`conversational-manifest.test.ts:192-206`) uses an explicit `"single_shot"`; the default-mode branch of `assertNoConversationalFieldsOnSingleShot` (`manifest/index.ts:376-400`) is never exercised.
- **[Low] `AwaitingContext` immutability is tested only at the pure-function level** — `awaiting-context.test.ts` never exercises the SQL guard (`TERMINAL_IMMUTABLE_WHERE`, `journal/index.ts:128-129`) for a row already in `AwaitingContext`. If prior C3 suites cover the WHERE clause generically this is acceptable, but the H1-named test does not prove the new terminal state is actually protected by it.
- **[Low] `interaction_mode_in_place_change_fails_build` proves generic hash mismatch, not the mode flip specifically** — `conversational-manifest.test.ts:208-225` compares hashes of two different manifests; any content change would fail identically. The §5.7-specific claim (mode flip ⇒ new version) rides on A4's generic mechanism, which is legitimate, but the test would pass even if `interactionMode` were excluded from the hash.

## 6. Recommended Improvements

1. **[Medium] Type- and range-check the conversational Interaction fields** in `assertConversationalInteractionFields` (finite number, positive integer as appropriate per field), mirroring `assertEconomicsTypes`, and add one rejection test per malformed value class (§5.1; §3.10).
2. **[Medium] Wire `canReachAwaitingContext` into the journal transition API** — e.g. pass the manifest's `interactionMode` to `journalTransition`/`recordTerminalState` and refuse `AwaitingContext` for `single_shot` — or delete the dead helper and document where H2/H3 enforce reachability (§6.3, FR-010).
3. **[Medium] Reconcile `errors.ts` with the plan**: either revert the throw and rely on the type system plus the taxonomy-absence test (the string is not a `TaxonomyCode`, so refusal is already structural), or keep the guard and update `plan.md` Files/Consumes to record the A2-module edit honestly.
4. **[Low] Validate the `context_requested` payload with `validateContextRequest` in `pushTerminalEvent`** (or fail fast on a missing payload instead of defaulting to `[]`), or explicitly defer emission-time validation to H2 in the contract (§6.7.2).
5. **[Low] Strengthen the stream-level single_shot test** so the deny decision is made by production code (e.g. an adapter/broker path that attempts emission and surfaces the throw as a failed leg), not by the stub's internal downgrade.
6. **[Low] Replace the export-name-regex prohibition tests** with structural assertions that would actually fail on regression (e.g. scanning `src/` for new D1 migrations or Durable Object bindings, or asserting the §6.1 stage list is unchanged).
7. **[Low] Decide and test edge policies for the permitted key set**: reject duplicate entries, and state explicitly whether an empty `permittedKeySet` is legal for a `conversational` capability (currently accepted silently).

---

## 7. Review Resolution

### 7.1 Stage grouping

| Stage | Review items covered | Files / logic |
| --- | --- | --- |
| **H1-R1 — Numeric Interaction type/range** | Bugs #1; Missing Tests #1; Rec #1 | `src/manifest/index.ts` `assertConversationalInteractionFields` (finite positive integers); `test/conversational-manifest.test.ts` |
| **H1-R2 — AwaitingContext write-path reachability** | Arch Dev #1, #3; Missing Tests #5; Rec #2 | `src/journal/index.ts` wire `canReachAwaitingContext` into `isJournalTransitionAllowed` / `journalTransition` / `recordTerminalState`; `test/awaiting-context.test.ts`; `test/journal.test.ts` SQL immutability |
| **H1-R3 — Reconcile errors.ts** | Bugs #3; Arch Dev #2; Rec #3 | Revert throw in `src/errors.ts`; unknown/`context_requested` → `internal_error`; Spec Kit plan CONSUMED unchanged; `taxonomy.test.ts` T24; `context-requested-terminal.test.ts` |
| **H1-R4 — Validate context_requested payload** | Bugs #2; Rec #4 | `src/adapter.ts` `pushTerminalEvent` calls `validateContextRequest`; fail on missing/malformed (no `[]` default) |
| **H1-R5 — Production-gated single_shot stream** | Missing Tests #2; Rec #5 | `test/helpers/adapter-stub.ts` always calls `pushTerminalEvent`; stream test spies production gate |
| **H1-R6 — Prohibition / edge / omitted-mode / hash** | Missing Tests #3, #4, #6; Rec #6, #7 | Structural prohibition tests; omitted-`interactionMode` rejection; empty/duplicate `permittedKeySet`; mode-only hash flip |

Every numbered review item is covered. No escalation — fixes stay within §5.1 / §5.4 / §5.5 / §5.7 / §6.3 / §6.7.2 / §6.7.4 / A14 and Spec Kit contract extensions.

### 7.2 Test cases created first

- **H1-R1:** `conversational_numeric_fields_reject_malformed_values` — wrong type, negative, zero, non-integer per field.
- **H1-R2:** Mode-gated `isJournalTransitionAllowed`; write-path refuse for `single_shot`; SQL `TERMINAL_IMMUTABLE_WHERE` after `AwaitingContext`.
- **H1-R3:** T24 / taxonomy-absence assert classify-to-`internal_error` (no throw).
- **H1-R4:** `context_requested_payload_must_conform` — missing and malformed rejected; conforming accepted.
- **H1-R5:** Stream case spies `pushTerminalEvent(..., "context_requested", "single_shot")` then ends with a permitted terminal.
- **H1-R6:** Omitted-mode rejection; empty/duplicate permitted keys; structural no-stage / no-conversation-table / no-extra-DO; mode-only hash change.

### 7.3 Fix implemented

- Manifest loader type/range-checks conversational numeric limits; rejects duplicate permitted keys; documents empty allowlist as legal.
- Journal write APIs take `interactionMode` and refuse `AwaitingContext` for `single_shot`.
- Removed the `buildErrorBody` throw; restored A2 classify-unknown behaviour; Spec Kit records `errors.ts` CONSUMED unchanged.
- Emission path validates context-request payload against the shared schema.
- Stub no longer silently downgrades; production gate owns the deny.
- Spec Kit `spec.md` / `plan.md` / `tasks.md` / `quickstart.md` / contracts updated.

### 7.4 Verification

Full `ai-platform` `npm test`: verify-manifests **2 files / 4 tests**; node Vitest **41 files / 615 tests**; workers Vitest **19 files / 268 tests** (includes load **10 tests**) — all passed. Modified: `src/{manifest,journal,errors,adapter}.ts`, H1 tests + `journal.test.ts` / `taxonomy.test.ts` / `conversational-journaling.test.ts`, Spec Kit under `specs/044-conversational-manifest-schema/`, this resolution appendix.
