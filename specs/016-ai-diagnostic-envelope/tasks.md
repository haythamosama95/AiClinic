# Tasks: Diagnostic envelope — error taxonomy, request reference, trace propagation (A2)

**Input**: Design documents from `/specs/016-ai-diagnostic-envelope/`

**Prerequisites**: `plan.md` (required), `spec.md` (required). No `research.md`, no `data-model.md`,
no `contracts/` — the plan's Project Structure → Documentation names `quickstart.md` only (the
contracts are TypeScript modules; verification is the CI suite).

**Tests**: Every case in the spec's Test plan is a task. The template's optional-tests note does
not apply to this platform (Delivery Plan §3.10). The 18 per-§5.4-code cases (T1–T18) are written as a
single table-driven task that iterates the taxonomy table — the same pattern A1 used to hold three
distinct invariants in one `env-deploys.test.ts`; the rule requiring one task per *spy/absence* case
is honoured by keeping the genuine redaction/normalisation cases below as their own tasks.

**Organization**: One slice, one user story (US1). Tasks are grouped by phase, not by story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 (the single story)
- Include exact file paths in descriptions

## Path Conventions

- **Flutter desktop app**: `frontend/lib/`, `frontend/test/` — *not touched by A2*
- **Supabase backend**: `backend/migrations/`, `backend/functions/`, `backend/tests/` — *not touched by A2*
- **AI Gateway Worker**: `ai-platform/src/`, `ai-platform/migrations/` *(none in A2)*, `ai-platform/test/`
- A2 extends the `ai-platform/` tree A1 created (plan Project Structure → Source Code); it creates
  three `src/` modules and five `test/` files, and modifies `src/worker.ts` to wire the envelope in.

---

## Phase 1: Setup

**Purpose**: Omitted. A1 already created the `ai-platform/` tree, `package.json` (Vitest pool-workers
is present), `tsconfig.json`, and `wrangler.toml`. The plan's Files section names no new shared
infrastructure for A2 — only three new modules and five new test files, which the Tests phase
creates directly.

---

## Phase 2: Tests

**Purpose**: One task per named test in the spec's Test plan, written to fail before the code
exists (Delivery Plan §3.10). All at the Contract-tests / unit-CI layer (§13.5).

- [X] T001 [P] [US1] Write `ai-platform/test/taxonomy.test.ts` — the 18 per-code cases (T1–T18)
      as a single table-driven `describe.each` over the §5.4 table, asserting for each code its
      HTTP status, retryability, quota-consumption flag, and body code; plus case T19
      (an unrecognised code is treated as `internal_error` and never surfaced raw); plus case T24
      (no error body is built for `context_requested`); plus case T26 (`rate_limited` carries
      `retry_after` and not the period reset, `quota_exhausted` carries the period reset and not
      `retry_after`); plus case T29 (`retry_safe` is false for §5.4 "Retryable" values `No` and
      `—`, true for every other value). Written red — fails before `src/errors.ts` exposes the
      table and builder. Satisfies FR-001, FR-002, FR-003, FR-005, FR-006, FR-008, FR-009.
      Proved by the 23 named cases T1–T19, T24, T26, T29 turning green together.
- [X] T002 [P] [US1] Write `ai-platform/test/error-body.test.ts` — case T20: every error body is
      the JSON object `{"code","request_reference","trace_id","retry_safe"}` with `retry_safe` a
      boolean, for a representative sample of codes. Written red — fails before `src/errors.ts`
      builds a body. Satisfies FR-004 (and the Clarification Q1 field-name pin). Proved by T20.
- [X] T003 [P] [US1] Write `ai-platform/test/reference.test.ts` — case T21: a generation run of
      20,000 references where every value matches
      `^[0-9A-HJKMNP-TV-Z]{4}-[0-9A-HJKMNP-TV-Z]{4}$`, is uppercase, omits `I`/`L`/`O`/`U`, and
      is unique across the run (draw count chosen so birthday false-fail ≪ 0.1% over 32⁸; not
      1,000,000 which is flaky under strict uniqueness); plus case T28 (a lowercase or
      `I`/`L`/`O`-confused input normalises to the stored reference form). Written red — fails
      before `src/reference.ts` exposes the generator and the normalisation map. Satisfies FR-010,
      FR-011, FR-013. Proved by T21 and T28.
- [X] T004 [P] [US1] Write `ai-platform/test/trace.test.ts` — case T22 (a supplied trace id
      appears on every log line emitted for that request); plus case T23 (an absent trace id is
      generated as a ULID — 26-char Crockford-base32 — and propagated identically to a
      caller-supplied id). Case T22 is a *spy/absence* assertion (no log line is missing the id),
      kept from being folded into T23. Written red — fails before `src/trace.ts` exposes the
      resolver. Satisfies FR-014, FR-016. Proved by T22 and T23.
- [X] T005 [P] [US1] Write `ai-platform/test/log-redaction.test.ts` — case T25 (a malformed
      request body is rejected by the adapter's own parsing and produces no taxonomy-coded error
      body — no code maps to bare `400`); plus case T27 (no log line carries prompt text, context
      payload, or credentials, even for a request that contained them). Case T27 is a
      *spy/absence* assertion (the prohibition the §13.1 *Structured logs* row places on the
      payload fields), kept as its own assertion inside this task. Written red — fails before
      `src/worker.ts` resolves the trace id at the top of `fetch` and routes the error/log
      emission. Satisfies FR-005, FR-015. Proved by T25 and T27.

**Checkpoint**: All twenty-nine named cases exist and fail red.

---

## Phase 3: Implementation

**Purpose**: One task per implementation unit in the plan's Files section, each satisfying the
test(s) written red above. The order follows the plan's Sequencing (errors → reference → trace →
worker wiring), so each test file turns green against its module.

- [X] T006 [P] [US1] Implement `ai-platform/src/errors.ts` — the §5.4 taxonomy table as a typed
      record keyed by code (columns: meaning, HTTP status, retryability, quota-consumption flag,
      client behaviour) and the `retry_safe` boolean mapping (`false` for "Retryable" values `No`
      and `—`, `true` for every other value). No code maps to bare `400`; `context_requested` is
      absent from the table and the builder refuses it; an unrecognised code is classified as
      `internal_error`. The error-body builder emits `{"code","request_reference","trace_id",
      "retry_safe"}`. `499` for `cancelled` is never written to a live socket — the module exposes
      it only as the journaled terminal value; the live emission is the caller's, not the
      envelope's. Satisfies FR-001, FR-002, FR-003, FR-004, FR-005, FR-006, FR-007, FR-008, FR-009.
      Proved by T001 (T1–T19, T24, T26, T29) and T002 (T20).
- [X] T007 [P] [US1] Implement `ai-platform/src/reference.ts` — the Crockford-base32
      request-reference generator: eight symbols (two hyphen-separated groups of four) from the
      alphabet `0123456789ABCDEFGHJKMNPQRSTVWXYZ` (omits `I`, `L`, `O`, `U`), drawn from
      `crypto.getRandomValues` (CSPRNG, not a counter or timestamp). Plus the normalisation map
      for lookup: case-fold up, then `I`/`L` → `1`, `O` → `0`. The generator is stateless; the D1
      unique index and the stored-row retry-on-conflict belong to A6 and are deliberately not
      implemented here (spec Out of Scope). Satisfies FR-010, FR-011, FR-012, FR-013. Proved by
      T003 (T21, T28).
- [X] T008 [P] [US1] Implement `ai-platform/src/trace.ts` — the trace-id resolver: accept a
      caller-supplied trace id unchanged; on absence, generate a ULID-format string (26-char
      Crockford-base32, including the 48-bit timestamp prefix per the ULID spec) from
      `crypto.getRandomValues`, propagated identically to a caller-supplied id, so every log line
      carries a trace id regardless of caller behaviour. Structured-log emission carries
      `request_reference`, `trace_id`, installation, capability, prompt version — and nothing of
      the payload. Satisfies FR-014, FR-015, FR-016. Proved by T004 (T22, T23) and the log-line
      payload invariant asserted by T005 (T27).
- [X] T009 [US1] Modify `ai-platform/src/worker.ts` to wire the diagnostic envelope into the
      existing fetch path: call the trace-id resolver at the top of `fetch` (accepting or
      generating per FR-016), thread the resolved id into the structured-log emission and the
      error-body builder, and ensure the adapter's own parsing rejects a malformed body before any
      taxonomy code is built (no bare `400`). No new route, no new binding, no env-topology or
      health-endpoint change — A1's `Consumes` binding is preserved (Delivery Plan §2.3).
      Satisfies FR-004, FR-014, FR-015, FR-016 and the adapter-parse rejection at FR-005. Proved
      by T005 (T25, T27). *(Depends on T006, T007, T008 — the modules its wiring imports.)*

**Checkpoint**: All twenty-nine named cases pass green.

---

## Phase 4: Verification

**Purpose**: Run the whole suite, including every prior slice's suite (Delivery Plan §3.10).

- [X] T010 [US1] Run the full AI-platform suite (`vitest run` in `ai-platform/`): confirm A2's
      twenty-nine cases (T001–T005) are green and confirm A1's four cases
      (`env-deploys.test.ts` T1/T3/T4 and `health.test.ts` T2) remain green — a regression in A1
      is a hard fail. Satisfies the §3.10 "every prior suite green" rule for A2. Proved by the
      green run itself.

**Checkpoint**: Slice complete and provable by an automated test a human can read and believe
(Delivery Plan §2.2).

---

## Documentation

**Purpose**: The `quickstart.md` artifact the plan's Project Structure → Documentation names. Written
after Verification is green; it documents the passing state for a human reviewer.

- [X] T011 [US1] Write `specs/016-ai-diagnostic-envelope/quickstart.md` per
      `.specify/templates/ai-platform-quickstart-template.md`: a brief of what A2 implemented (the
      §5.4 error taxonomy, error-body contract, request-reference generator, trace-id resolver, and
      worker wiring), a files-to-review table (A2 files only), slice-only `npx vitest run` commands
      for the five A2 test files (48 passing), how to inspect the three contract modules and the
      `worker.ts` integration, and no manual-validation section (CI is the verification path).
      Slice-only scope: no prior-slice files, combined test counts, or full-suite `npm test`. Satisfies
      the plan's Documentation artifact. Proved by a reviewer being able to reproduce the green run
      from the doc alone.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup**: Omitted — A1's `ai-platform/` tree is the prerequisite, already merged.
- **Tests (Phase 2)**: Depends only on the `ai-platform/` tree existing (A1). T001–T005 are all
  `[P]` — five distinct files, no dependencies among them. Written red before Phase 3.
- **Implementation (Phase 3)**: Depends on Phase 2 tests existing red. T006–T008 are `[P]` (three
  independent contract modules). T009 (the `worker.ts` wiring) depends on T006, T007, T008 — it is
  the integration seam.
- **Verification (Phase 4)**: Depends on Phase 3.
- **Documentation**: Depends on Phase 4 (Verification green). T011 documents the now-passing suite.

### Within the Slice

- Tests are written red before the implementation that makes them green (Delivery Plan §3.10).
- The taxonomy table (`errors.ts`) lands first conceptually (its builder feeds the body tests);
  then the reference generator; then the trace resolver; the `worker.ts` wiring last, because it
  imports all three.
- No model/service/endpoint layering — A2 has three contract modules and one integration file.

### Parallel Opportunities

- T001, T002, T003, T004, T005 are all `[P]` — five separate test files, no dependencies.
- T006, T007, T008 are all `[P]` — three separate contract modules, no dependencies among them
  (each module satisfies its own test file). T009 is the only Phase-3 task with dependencies.
- T011 runs after T010 — the quickstart documents the green suite, not the plan.

---

## Notes

- 11 tasks, well under the 25-task cap (Delivery Plan §6.3 stop condition 5).
- Every task traces to a spec FR or a named test; no task adds a requirement the spec does not
  name. The 18 per-§5.4-code cases (T1–T18) are parametric inside T001 — same pattern A1 used to
  hold three invariants in one `env-deploys.test.ts`; no case is dropped.
- `quickstart.md` is always produced (ai-platform-tasks Documentation phase); no `data-model.md`/
  `contracts/`/`research.md` — the plan names none of them for A2.
- No Polish phase: cleanup, refactoring, and generic "security hardening" are forbidden — each
  would be work the spec does not name (R-20).
- No Foundational phase: A2 has `Needs: A1`; the prerequisite is the merged A1 tree, not new
  shared infrastructure.
- The D1 unique index on `request_reference` and the stored-row retry-on-conflict are deliberately
  absent — they are A6's contract (spec Out of Scope). Adding them here would be pull-forward
  (Delivery Plan §2.3, R-20).
- Commit after each task or logical group; the slice is complete at the T011 quickstart, after T010
  green run.