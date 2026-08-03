# Tasks: Canonical inference representation (slice A3)

**Input**: Design documents from `/specs/017-ai-canonical-inference/`

**Prerequisites**: `plan.md` (required), `spec.md` (required). No `data-model.md` (A3 defines no D1 entities); no `research.md` (the research is `17-ai-platform.md` §5.3/§9.10, not redone here).

**Tests**: Tests are mandatory for this slice — one task per named case in the spec's Test plan (§3.11.1 row A3). The template's "Tests are OPTIONAL" note does not apply to the AI platform.

**Organization**: One slice is one user story — there is one `[US1]` label and no cross-story parallelism phase.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to — here always `[US1]`
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/`
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/`
- **Cloudflare Worker (AI gateway)**: `ai-platform/src/`, `ai-platform/migrations/`, `ai-platform/test/`
- Paths assume the canonical AiClinic architecture — the gateway is a sibling of `frontend/` and `backend/` (delivery plan §7.1), and A3 adds files only under `ai-platform/` and `specs/017-ai-canonical-inference/`.

---

## Phase 1: Setup

**Purpose**: Create the module the plan's Files section names, before the tests that import it.

- [X] T001 [US1] Create `ai-platform/src/contracts/canonical.ts` with the field-name manifest only — one entry per §5.3 canonical element enumerating its **Field** identifiers (`parts`, `formatDirective`, `samplingConstraints`, `maxOutputTokens`, `stopConditions`, `toolDeclarations`, `stream`, `deadline`, `correlationIds` for the request; `sequenceNumber`, `kind`, `payload`, `terminal` for the chunk; `finalContent`, `usage`, `providerModel`, `finishReason`, `providerRequestId`, `timing` for the result; `taxonomyCode`, `retryability`, `providerNative`, `consumedBudget` for the error). No types, no codec yet — the guard test (T002) exercises this manifest. Satisfies FR-002, FR-009; proven by T-A3-05 / T-A3-10.

---

## Phase 2: Tests

**Purpose**: One task per named case in the spec's Test plan, written to fail before the implementation units land (delivery plan §2.2; §3.11.1 row A3). All seven live in one file, `ai-platform/test/canonical.test.ts`, so no `[P]` — they share the file and are written in the order below.

- [X] T002 [US1] Write `T-A3-05 provider-shaped field name rejected` in `ai-platform/test/canonical.test.ts`: asserts the manifest contains no key equal to a known provider-shaped token (`messages`, `completion`, `n`, `frequency_penalty`, `top_p`, `logprobs`) and that introducing one makes the guard fail. Fails until the manifest in T001 is present and clean. Proves FR-009 / SC-002.
- [X] T003 [US1] Write `T-A3-06 chunk kinds exhaustive` in `ai-platform/test/canonical.test.ts`: asserts the chunk-kind set is exactly `{text_delta, partial_structured, usage, provider_note}` and that any other kind is rejected by a closed-set check. Fails until T006 lands the kind union. Proves FR-005 / SC-003.
- [X] T004 [US1] Write `T-A3-07 terminal flag exactly once per sequence` in `ai-platform/test/canonical.test.ts`: feeds an empty sequence, a sequence with zero terminal flags, and a sequence with two terminal flags, asserting each is rejected; one terminal flag is accepted. Fails until T006 lands the terminal-flag invariant helper. Proves FR-004 / SC-004 / §5.5 rule 4.
- [X] T005 [US1] Write `T-A3-01 round-trip canonical request` in `ai-platform/test/canonical.test.ts`: encodes a fixture canonical request through the owned codec and decodes it back, asserting every §5.3 field survives byte-for-byte with no extra keys. Fails until T007's codec and T006's request type exist. Proves FR-001, FR-003 / SC-001.
- [X] T006 [US1] Write `T-A3-02 round-trip canonical stream chunk` in `ai-platform/test/canonical.test.ts`: same round-trip for a chunk of each of the four kinds, asserting `sequence number`, `kind`, `payload`, `terminal flag` survive. Fails alongside T007/T006. Proves FR-004 / SC-001.
- [X] T007 [US1] Write `T-A3-03 round-trip canonical result` in `ai-platform/test/canonical.test.ts`: round-trips a canonical result fixture, asserting `final content`, `usage counters`, `provider+model`, `finish reason`, `provider request id`, `timing breakdown` survive. Fails alongside T007/T006. Proves FR-006 / SC-001.
- [X] T008 [US1] Write `T-A3-04 round-trip canonical error` in `ai-platform/test/canonical.test.ts`: round-trips a canonical error fixture, asserting `taxonomy code`, `retryability`, `provider-native code and message`, `consumed budget flag` survive, and that the `taxonomy code` value is validated against A2's `TaxonomyCode` type (an unrecognised code is rejected). Fails alongside T007/T006. Proves FR-007 / SC-001.

---

## Phase 3: Implementation

**Purpose**: One task per implementation unit the plan's Files section names, ordered so each test is satisfiable.

- [X] T009 [US1] In `ai-platform/src/contracts/canonical.ts`, define the four canonical element interfaces (`CanonicalRequest`, `CanonicalStreamChunk`, `CanonicalResult`, `CanonicalError`) with **real per-field TypeScript types** (not `unknown`), keyed by the amended §5.3 Field identifiers; type `CanonicalError.taxonomyCode` as the `TaxonomyCode` imported from `ai-platform/src/errors.ts` (A2's frozen set, consumed not redefined); export `CANONICAL_MESSAGE_ROLES`. Adapters/composer consume typed fields without `as` casts (T-A3-09). T-A3-10 pins identifiers vs prose. Satisfies FR-001, FR-003, FR-004, FR-006, FR-007; unblocks T005..T008.
- [X] T010 [US1] In `ai-platform/src/contracts/canonical.ts`, add the closed chunk-kind union (`text_delta | partial_structured | usage | provider_note`) and the terminal-flag invariant helpers (`assertExactlyOneTerminal`, plus the empty/multiple rejection predicates). The kind union is exhaustive — a chunk of any other kind is a type error. Satisfies FR-005 and the §5.5 rule 4 invariant; unblocks T003, T004.
- [X] T011 [US1] In `ai-platform/src/contracts/canonical.ts`, add the thin owned JSON codec (`encodeCanonicalRequest`/`decodeCanonicalRequest`, and the analogous pairs for chunk, result, error), driven by the T001 manifest so only manifest-declared keys are emitted and any provider-shaped or unknown extra key is **rejected** fail-closed on encode and decode (T-A3-05 codec path; T-A3-08). No dependency beyond the types from T009/T010. Satisfies FR-008; unblocks T005..T008.

---

## Phase 4: Verification

**Purpose**: Evidence the slice is done — the whole suite green, including prior slices (delivery plan §3.10).

- [X] T012 [US1] From `ai-platform/`, run `npm test` and confirm all of A1 (`env-deploys`, `health`), A2 (`error-body`, `taxonomy`, `log-redaction`, `reference`, `trace`), and A3 (`canonical`) suites pass. A regression in any prior suite is a hard fail, not a rebuild. Satisfies the spec's Independent Test and Success Criteria as a whole.

---

## Phase 5: Documentation

**Purpose**: Every slice produces `quickstart.md`; the plan's Files section also names the frozen-shapes contract doc.

- [X] T013 [P] [US1] Write `specs/017-ai-canonical-inference/contracts/canonical-shapes.md` documenting the four frozen §5.3 wire shapes (field names, contents, and the closed chunk-kind set) so a later slice's Consumes binds to a frozen artifact rather than prose. Derived from the implemented `canonical.ts`; no requirement added. Traces to the spec's **Freezes** entry.
- [X] T014 [US1] Write `specs/017-ai-canonical-inference/quickstart.md` per `.specify/templates/ai-platform-quickstart-template.md`: §1 what A3 implemented (the canonical types + guard test); §2 files to review (`ai-platform/src/contracts/canonical.ts`, `ai-platform/test/canonical.test.ts`, `contracts/canonical-shapes.md`); §3 run this slice's tests (`npx vitest run test/canonical.test.ts`, 16 passing); §4 how to inspect the frozen shapes (`contracts/canonical-shapes.md`, the closed kind union). Omit Prerequisites and Manual validation — `npx vitest run` is the only verification path and A3 exposes no behaviour beyond CI. Slice-only scope: no prior-slice files or combined test counts. Traces to the Documentation task the plan names.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: T001 has no dependency — start immediately.
- **Phase 2 (Tests)**: Each test task depends on T001 at minimum (it imports the module); they are written to fail until the matching implementation in Phase 3 lands, which is the point. Order within Phase 2 follows the test file's construction, not dependency on real code.
- **Phase 3 (Implementation)**: T009 depends on T001; T010 and T011 depend on T009. After each lands, its corresponding Phase 2 test goes green.
- **Phase 4 (Verification)**: T012 depends on T009, T010, T011 (all green) and transitively on every Phase 2 test passing.
- **Phase 5 (Documentation)**: T013 and T014 depend on T012 (the docs describe shipped, verified work).

### Within the Slice

- Tests are written before or alongside the code they cover (delivery plan §3.10) — T002 is written against the T001 manifest before T009..T011 exist, then goes green as implementation lands.
- No task pulls work forward from a later slice: no adapter, no composer, no stream broker, no D1/R2/DO work.

### Parallel Opportunities

- T013 and T014 are `[P]` — different files (`contracts/canonical-shapes.md` vs `quickstart.md`), both depend only on T012, no shared input.
- No other `[P]` opportunities exist: the seven tests share one file and the three implementation tasks mutate the same `canonical.ts`, so ordering is required to keep each diff reviewable against one named part of §5.3.

---

## Notes

- A3 is a contract-only slice: it performs zero D1 inserts, zero R2 puts, zero Durable Object round trips, so the platform's I/O budgets are untouched (§6.1, §7.5, §13.6).
- The spec's `## Clarifications` entries (manifest-driven codec; single `contracts/canonical.ts` file) are followed in T011 and the file layout, but each task traces to an `FR-###`, never to a clarification — clarifications are not requirements.
- Hard cap respected: 14 tasks, well under 25.