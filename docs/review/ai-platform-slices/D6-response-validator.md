# Slice Review Report — D6: Response Validator, Bounded Repair, and Structured Output Modes

**Spec:** `specs/033-response-validator/spec.md` · **Branch:** `ai/033-d6-response-validator` · **Canonical:** §4.3.9, §6.4, §5.1

## Executive Summary

**Verdict: D6 only partially meets its "Done when" criteria.** The four-phase validator and the bounded-repair loop are correctly implemented *as library code* and well unit-tested, and the structured broker correctly emits provisional `partial_structured` events with a self-contained validated terminal payload. However:

- **Bounded repair is not wired into any shipped code path.** `validateAndRepair` is called only from tests; the D6-owned structured broker calls `runValidationPhases` directly, has **no `repairPolicy` field and no `reask` seam at all**, and fails straight to `validation_failed` — so "a single budgeted re-ask … is attempted only where the manifest allows it" is not true of any production-reachable path in this slice.
- **Repair cost "counting" is decorative** — the sink is fed a caller-supplied constant, never actual re-ask usage.
- Several required tests are weak or vacuous (phase ordering, `structured_atomic` progress, no-per-request-state, not-assembled-from-chunks).

**Issue counts by severity:** Critical: 1 · Bugs (high/medium): 6 · Architectural deviations / doc mismatches: 4 · Weak/missing tests: 6 · Improvements: 7.

Overall code quality is good: clean closure-scoped state (no per-request server state), one-terminal-event discipline preserved, prose path untouched, no §9.14 mechanisms added, no provider/model names hard-coded.

## Critical Issues

1. **Structured completion path cannot perform bounded repair; repair is wired nowhere in production code** (`ai-platform/src/stream/structured.ts:53-60` — `StructuredValidationConfig` has no `repairPolicy`; `:197-199` — `handleValidationFailure` → immediate `validation_failed`; `:203-217` — calls `runValidationPhases`, never `validateAndRepair`). Repo-wide, `validateAndRepair` is referenced only by `test/response-validator.test.ts` and `test/conversational-response-validator.test.ts` — no production caller exists. §4.3.9 (lines 1395–1399) is explicit: "On failure the validator may attempt a **bounded repair** … Whether repair is allowed is a per-capability manifest decision," and the done-when requires "a single budgeted re-ask with the validation errors appended is attempted only where the manifest allows it." The repair contract is the riskiest half of this slice (cost, journaling, cap discipline). It exists only as an unwired library function, and the one D6-owned runtime path (structured completion) is built so it *structurally cannot* repair — there is no port, no policy input, no attempt journaling. A manifest that declares `repairPolicy.allowed: true` gets identical behavior to one that disallows repair on every shipped path. Clarification Q2 defers wiring the port "to invocation" later, but nothing in the structured broker even exposes the seam for that future wiring, so the done-when sentence is untestable and untrue in the delivered slice.

## Bugs

1. **`reask` exceptions propagate instead of failing terminally** (`ai-platform/src/validate/index.ts:116`). `currentOutput = await input.reask([result.failure]);` sits outside any try/catch. A throwing re-ask (provider error, abort) rejects `validateAndRepair` with an untyped exception instead of producing `validation_failed`. Resilience gap: the repair path can crash the validation boundary.

2. **Repair cost is a caller-supplied constant, not actual usage** (`ai-platform/src/validate/index.ts:38` — `repairCostPerAttempt?: { tokens; cost }`; `:112-114` — sends the constant, defaulting to `{tokens: 0, cost: 0}`). The `ReaskPort` (`:30`) returns only `AssembledOutput` — it *cannot* carry usage — so real repair generation cost can never be counted. §4.3.9's rationale ("an unbounded repair loop is an unbounded bill") and FR-006 ("repair cost MUST be counted") are not substantively met; with the default, repair cost is silently counted as zero.

3. **Declared schema/rule refs that don't resolve are silently skipped** (`ai-platform/src/validate/phases.ts:199-210` — schema runner missing → phase passes; `:213-223` — rule runner missing → rule passes). A capability that *declares* a business rule whose ref is unregistered validates as clean. §4.3.9 says "business-constraint checks the capability declares" — a declared-but-unresolvable check should fail closed (or at least surface), not pass silently. This is a data-integrity-relevant fail-open.

4. **Truncated-output guard is dead on the structured broker path** (`ai-platform/src/stream/structured.ts:205` hardcodes `output: { raw: assembled, transportValid: true }`; `truncated` is never set, so the `output.truncated === true` check at `phases.ts:158` can never fire for structured completions). The only remaining trigger is a literal `_truncated: true` property inside the document (`phases.ts:182-187`) — i.e., trusting the model to confess truncation. A provider hitting `maxOutputTokens` mid-JSON fails as `transport_parse` only by accident of malformed JSON; clean-but-truncated output (e.g. valid JSON missing trailing sections) passes unless a business rule catches it.

5. **Refusal "prefixes" are matched as arbitrary substrings** (`ai-platform/src/validate/phases.ts:174-179` uses `raw.includes(prefix)` despite the field name `refusalPrefixes`). Any legitimate clinical text containing the phrase mid-sentence (e.g. quoting a patient) fails validation. False-positive-prone; either match at start or rename the contract.

6. **Terminal failure result discards the failure detail** (`ai-platform/src/validate/index.ts:60-62, 92-96`). The `validation_failed` result carries only `phase`, dropping `message` (and all but the last phase's error). Journaling/support lookup (§6.3: states journaled so support is "a lookup rather than an investigation") gets almost nothing to persist.

## Architectural Deviations

1. **[Documentation issue] Contract/plan/quickstart name the wrong module.** `specs/033-response-validator/contracts/response-validator.md:91` ("**Module:** extended `ai-platform/src/stream/index.ts`"), `plan.md` Files table (line 107) and task T023 say structured emission *extends* `stream/index.ts`; the implementation is a **new sibling** `ai-platform/src/stream/structured.ts`, and `stream/index.ts` contains zero structured-mode code. The quickstart's own inspect command (`quickstart.md:76`, greps only `src/stream/index.ts`) would find nothing. The frozen contract — the artifact H2/E4 bind to — points consumers at the wrong file.

2. **Duplicated broker instead of extension (incorrect abstraction / tech debt).** `structured.ts` re-implements `StreamChunk`, `ChunkSource`, all sink interfaces, heartbeat handling, cancel/credit/journal sequencing (~350 lines) in parallel with `stream/index.ts`. Its own header comment (`structured.ts:11-17`) admits it "mirrors the NEW prose broker API that the parent rewrite will land on `./index`" — i.e., it is scaffolding for an unlanded rewrite. Two brokers must now be kept in sync for every cross-cutting fix (e.g. the prose broker's `abortableAsyncIterate` defense at `stream/index.ts:137-176` against signal-ignoring sources was *not* replicated in `structured.ts:253-306`, which iterates the source directly — `run()` can hang on a misbehaving source even though the terminal event is saved by the synchronous `disconnect`). Also `guardThresholds` is a *required* option that is documented as "unused on the structured path" (`structured.ts:70-71`) — a leaky forced-compatibility parameter.

3. **H2 conversational logic inserted into D6's frozen phase module.** `phases.ts:2, 56-92, 106-134` (`tryParseContextRequest`, the `conversational` + prose branch) implements context-request parsing — H1/H2 scope per the spec's own Out-of-Scope (spec.md lines 177–178) and the contract's "Consumers" table. Noted as an *interaction*: the contract permits later slices to consume but not reorder/skip phases; embedding H2 behavior inside phase 1 of the frozen module blurs that ownership boundary (D6's `parseOutput` now has behavior D6 never specified or tested). Flag for ownership clarity, not a behavioral violation.

4. **No deviation on the remaining hard invariants (verified clean):** no per-request server-side state (all state is closure-local per broker/connection, matching D4's pattern); invalid content never reaches the client on any code path (broker emits `failed` with only a taxonomy code — `structured.ts:186-195`); terminal payload is produced by a single `JSON.parse` of the full assembled text, not stitched from emitted partials (`structured.ts:220-235`); no §9.14 deferred mechanisms introduced; manifest Output fields (`mode`, `outputSchemaRef`, `businessValidationRuleRefs`, `repairPolicy`) exist in `src/manifest/index.ts:56-61` and `validation_failed` pre-exists in the A2 taxonomy (`src/errors.ts:16`).

## Missing or Weak Tests

Required case list, case by case:

**Validator**
- valid output passes — **COVERED** (`T-D6-01`).
- parse failure — **COVERED** (`T-D6-02`).
- schema violation — **COVERED** (`T-D6-03`).
- one case per declared business rule — **COVERED** (`T-D6-04`, four subcases: enumeration, referential, numeric range, required section).
- one case per safety guard — **COVERED** (`T-D6-05`…`T-D6-09`; leaked instruction, refusal, empty, truncated, injection echo).
- the four phases run in the stated order — **WEAK** (`T-D6-10`, `response-validator.test.ts:507-537`). The fixture fails phase 1; the assertion only proves `transport_parse` precedes `schema`. Ordering among phases 2→3→4 (schema→business→safety) is never exercised — a regression swapping business and safety would pass this suite.
- invalid content is never emitted — **COVERED** (`T-D6-11`, four failure fixtures, plus per-case `assertNoInvalidSuccessPayload`).

**Repair**
- repair allowed → one re-ask with errors appended → success — **COVERED** (`T-D6-12`; asserts single call and non-empty errors argument).
- repair disallowed → immediate `validation_failed` — **COVERED** (`T-D6-13`; asserts zero reask calls).
- repair fails → `validation_failed` — **COVERED** (`T-D6-14`).
- attempt cap enforced and journaled — **COVERED** (`T-D6-15`; `maxAttempts: 2`, asserts exactly 2 calls and journal records `[1, 2]`).
- repair cost counted against the request — **WEAK** (`T-D6-16`, `response-validator.test.ts:713-738`): the test injects the constant `{tokens: 120, cost: 0.002}` and asserts the sink echoes it. It proves plumbing, not counting — the implementation cannot count real usage (Bug 2).

**Output modes**
- `structured` partials all provisional — **COVERED** (`T-D6-17`).
- terminal carries whole validated document — **COVERED** (`T-D6-18`).
- `structured_atomic` emits progress only — **WEAK/vacuous** (`T-D6-19`, `structured-modes.test.ts:249-252`): `expect(heartbeats + progress).toBeGreaterThanOrEqual(0)` is true for *every* possible implementation, including one emitting nothing. The no-`partial_structured` assertion is real; the positive "emits progress/heartbeat" requirement is effectively untested.
- client ignoring chunks still correct — **COVERED** (`T-D6-20`).
- terminal payload not assembled from chunks — **WEAK** (`T-D6-21`): asserts `_assembledFromChunks === false`, a self-declared literal written by the same code being tested (`structured.ts:229`), plus reference-inequality. A behavioral proof would make chunk content diverge from the terminal document (e.g. a `regenerating` chunk after garbage, or provisional partials containing content absent from the final doc).
- error codes the slice emits (`validation_failed` only) — **COVERED** at validator level (T-D6-02/03/11/13/14/15 assert the code; `isTaxonomyCode` check in the helper).

**Coverage gaps beyond the named list:**
- **MISSING: broker-level validation failure.** No test feeds the structured broker a complete-but-invalid document and asserts a single `failed`/`validation_failed` terminal with no `completed` — the `completeStructured` → `handleValidationFailure` path (`structured.ts:214-216`) is untested, as are safety guards and business rules on the broker path (harness always uses empty `ruleRegistry`).
- **MISSING: reask-throws resilience** (Bug 1) and **unresolved-ref fail-open** (Bug 3).
- **WEAK: T-D6-22 no-per-request-state** (`structured-modes.test.ts:295-319`) — regex-matching *export names* (`/requestregistry|requeststate|sessiondo|durableobject/`) is a near-vacuous proxy; it would not catch an actual state object introduced under any other name.
- **WEAK: T-D6-24 prose-unchanged** — spying that the *structured* path doesn't call prose guards doesn't prove the prose path is intact; that guarantee rests on D4's own suite, which is acceptable but makes this test mostly ceremonial.

## Recommended Improvements

Prioritized:

1. **(P0) Give the structured broker a repair seam or document the deferral in the contract.** Add `repairPolicy` + `reask`/repair sinks to `StructuredStreamBrokerOptions` and route completion through `validateAndRepair` (`structured.ts:53-74, 200-217`), *or* amend `contracts/response-validator.md` to state explicitly that broker-level completion validation is repair-exempt until invocation wiring lands. Silence on this is what makes Critical 1 a contract break.

2. **(P0) Make the reask port return usage.** Change `ReaskPort` to resolve `{ output: AssembledOutput; usage: { tokens; cost } }` and feed the *returned* usage to `repairCostSink` (`validate/index.ts:30, 112-114`); delete `repairCostPerAttempt`. Strengthen T-D6-16 to assert the sink received the re-ask's reported usage.

3. **(P1) Fail closed on unresolved declared refs.** When `outputSchemaRef` is non-null but missing from the registry, or a declared rule ref has no runner, return a failure (schema/business phase) instead of skipping (`phases.ts:199-223`). Add a test.

4. **(P1) Wrap the reask call** in try/catch → `validation_failed` on throw (`validate/index.ts:116`); add a reask-throws test.

5. **(P1) Fix the vacuous/weak tests.** T-D6-19: assert `progress + heartbeat > 0`; T-D6-10: add fixtures failing (schema+business) and (business+safety) to prove the full 2→3→4 ordering; T-D6-21: use a `regenerating`-chunk scenario so terminal content provably differs from earlier chunks; T-D6-22: replace name-regex with a behavioral check (e.g. two concurrent brokers sharing no observable state).

6. **(P2) Consolidate the brokers or fix the docs.** Either fold structured emission into `stream/index.ts` as the contract/plan/quickstart claim, or update all three documents to name `stream/structured.ts`. If the broker stays separate, port `abortableAsyncIterate` and drop the required-but-unused `guardThresholds` option (`structured.ts:70-71`).

7. **(P2) Carry failure detail on the terminal result** (`validate/index.ts:60-62`) so C3 journaling can record *why* validation failed; match refusal prefixes at string start (`phases.ts:175`); propagate a truncation signal (e.g. finish-reason from the chunk source) into `AssembledOutput.truncated` so the truncated guard is reachable on the broker path (`structured.ts:205`).

---

## 1. Review Resolution

### 1.1 Stage grouping

| Stage | Review items covered | Files / logic |
| --- | --- | --- |
| **D6-R1 — Repair cost, reask resilience, failure detail** | Bugs #1, #2, #6; Recommended #2, #4; Rec #7 (failure detail); Weak T-D6-16; Missing reask-throws | `ai-platform/src/validate/index.ts`; `ai-platform/test/response-validator.test.ts` |
| **D6-R2 — Fail-closed refs + refusal prefix matching** | Bugs #3, #5; Recommended #3; Rec #7 (refusal); Missing unresolved-ref | `ai-platform/src/validate/phases.ts`; `ai-platform/test/response-validator.test.ts` |
| **D6-R3 — Structured broker repair seam + truncation** | Critical #1; Bugs #4; Recommended #1; Rec #7 (truncation); Missing broker validation failure | `ai-platform/src/stream/structured.ts`; `ai-platform/test/structured-modes.test.ts` |
| **D6-R4 — Broker parity (abortable iterate, drop guardThresholds)** | Architectural Deviations #2 (impl parts); Recommended #6 (port abortable; drop unused option) | `ai-platform/src/stream/structured.ts`; `ai-platform/test/structured-modes.test.ts` |
| **D6-R5 — Strengthen weak tests** | Weak T-D6-10, T-D6-19, T-D6-21, T-D6-22; Recommended #5; Weak T-D6-24 (kept; rests on D4 suite) | `ai-platform/test/response-validator.test.ts`; `ai-platform/test/structured-modes.test.ts` |
| **D6-R6 — Spec Kit docs** | Architectural Deviations #1, #2 (docs), #3; Recommended #6 (docs) | `specs/033-response-validator/{spec,plan,tasks,quickstart,contracts/response-validator}.md` |

Architectural Deviations #4 (verified clean) required no change.

### 1.2 Test cases created first

- **D6-R1:** T-D6-16 rewritten to assert sink receives reask-reported usage; T-D6-25 reask-throws → `validation_failed`; T-D6-27 failure carries `phase` + `message`.
- **D6-R2:** T-D6-06 start-anchored refusal + mid-sentence negative; T-D6-26 unresolved schema/rule refs fail closed.
- **D6-R3:** T-D6-28 broker validation failure terminal; T-D6-29 broker bounded repair seam; T-D6-30 truncation via `ChunkSource.wasTruncated`.
- **D6-R4:** Covered by existing cancel/stream harnesses after `abortableAsyncIterate` port and `guardThresholds` removal (harness no longer passes the unused option).
- **D6-R5:** T-D6-10 schema→business and business→safety ordering fixtures; T-D6-19 `progress + heartbeat > 0`; T-D6-21 regenerating-chunk divergence; T-D6-22 concurrent brokers observationally independent.
- **D6-R6:** Docs-only — no new production tests.

### 1.3 Fix implemented

- **D6-R1:** `ReaskPort` now returns `{ output, usage }`; deleted `repairCostPerAttempt`; reask throws map to `validation_failed`; terminal failure includes `message`.
- **D6-R2:** Missing schema/rule runners fail closed; refusal prefixes match `raw.trimStart().startsWith(prefix)`.
- **D6-R3:** Structured broker routes completion through `validateAndRepair` with `repairPolicy` + optional `reask`/sinks; `ChunkSource.wasTruncated()` feeds `AssembledOutput.truncated`.
- **D6-R4:** Ported `abortableAsyncIterate`; dropped required-but-unused `guardThresholds`.
- **D6-R5:** Weak tests strengthened as above; T-D6-24 left as structured-path prose-guard spy (D4 suite remains the prose integrity proof).
- **D6-R6:** Spec Kit artifacts now name `stream/structured.ts`, document the repair seam, fail-closed refs, reask usage, failure detail, and H2 ownership of conversational semantics vs D6-owned phases.

### 1.4 Verification

Full `ai-platform` suite: **59 test files**, **825 tests**, all passing (`npm test`: verify-manifests 4 + vitest 580 + workers 241).

D6-focused: `response-validator.test.ts` (29) + `structured-modes.test.ts` (11) = **40 passing**.

Modified/added test files: `ai-platform/test/response-validator.test.ts`, `ai-platform/test/structured-modes.test.ts`.
