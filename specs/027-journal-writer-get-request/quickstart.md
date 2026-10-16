# Quickstart: Journal writer, post-response detail, and get-request endpoint (C3)

C3 makes the journal the audit backbone of the AI gateway: it creates the durable `ai_request` row
synchronously at stage 9 before any inference work, stamps every §6.3 state transition, updates the
row with its terminal state at stage 15, and writes per-attempt `ai_attempt` rows, exactly one
`usage_event` row, and exactly one R2 payload envelope in a post-response continuation at stage 16
whose failure never fails the already-completed request. A guard rejection produces no journal row.
The get-request endpoint resolves a request reference to terminal state and, for completed requests,
the validated result from the envelope.

**Scope rule:** A quickstart documents **this slice only**. List only files this slice added or
modified, only this slice's test files, and only commands that run this slice's tests. Do **not**
include prior-slice files in the review table, combined test counts from earlier slices, prior-slice
regression commands, or diffs "against the <prior slice> baseline". Full-suite regression (this slice
plus every prior slice) belongs in the Verification task, not in `quickstart.md`.

**Numbering rule:** Number sections sequentially (`## 1.`, `## 2.`, …). Section **1** is always
**Architecture context**. When omitting Prerequisites or Manual validation, renumber the remaining
sections — do not leave gaps (e.g. 1, 2, 4, 5).

## 1. Architecture context

C3 implements the **C3** row in
[`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md)
§3.4, covering architecture sections **§4.3.11** (journal writer), **§6.1 stages 9, 15, 16**
(pipeline write-path timings), **§6.3** (state transition stamping), **§7.4** and **§7.4.1** (R2
payload envelope — one object per request), **§7.6** (indexed get-request lookup), and **§5.5**
(get-request API surface).

- **What the spec delivered** ([`spec.md`](./spec.md)): synchronous stage-9 `ai_request` insert
  before any inference work (`internal_error` on D1 failure); every §6.3 transition journaled with
  a timestamp; stage-15 terminal-state update; stage-16 post-response continuation writing N
  `ai_attempt` rows, exactly one `usage_event`, and exactly one R2 envelope keyed
  `request/{id}/envelope` with four sections (`context`, `prompt`, `attempts[]`, `result`) via
  `ctx.waitUntil` (failure swallowed); guard rejection produces no row; get-request endpoint
  resolving a reference through one indexed D1 lookup — completed returns state plus validated
  result, failed returns state plus terminal error code, cancelled returns state only, unknown
  returns not found.
- **What the plan scoped** ([`plan.md`](./plan.md)): one module `ai-platform/src/journal/index.ts`
  exporting `createRequestRow`, `journalTransition`, `recordTerminalState`,
  `writePostResponseDetail` (with inlined `buildEnvelope`), and `getRequest`; one
  `GET /v1/requests/{reference}` route in `worker.ts`; one integration test file with 18 named test
  suites (`T-C3-01` … `T-C3-18`); one frozen contract artifact; workers-pool tests against real
  Miniflare D1 and R2 bindings.

## 2. What was implemented

- **`createRequestRow()`** (`src/journal/index.ts`) — stage 9: synchronous D1 `INSERT` into
  `ai_request` before any inference work; returns `{ ok: true }` or `{ ok: false, code:
  "internal_error" }` on insert failure.
- **`journalTransition()`** (`src/journal/index.ts`) — §6.3 stamping: overwrites `state` and
  `updated_at` on every transition; terminal transitions also stamp `completed_at`.
- **`recordTerminalState()`** (`src/journal/index.ts`) — stage 15: updates the durable row with
  terminal state and optional `terminal_error_code`; no client-facing error.
- **`writePostResponseDetail()`** (`src/journal/index.ts`) — stage 16: schedules N `ai_attempt`
  inserts, one `usage_event` insert, one R2 `PutObject` (via inlined `buildEnvelope()`), and a
  `payload_pointer` update through `ctx.waitUntil`; failures swallowed.
- **`getRequest()`** (`src/journal/index.ts`) — read function: one indexed D1 lookup on
  `request_reference`; completed requests additionally fetch the `result` section from R2.
- **`GET /v1/requests/{reference}`** (`src/worker.ts`) — maps `getRequest()` results to JSON
  responses (200 for found states, 404 for unknown reference).

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level
traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/journal/index.ts` | Stage-9/15/16 writer functions, inlined `buildEnvelope`, `getRequest` |
| `ai-platform/src/worker.ts` | `GET /v1/requests/{reference}` route |
| `ai-platform/test/journal.test.ts` | 18 named `T-C3-*` test suites (ordering + spy) |
| `specs/027-journal-writer-get-request/contracts/journal.md` | Frozen envelope layout, get-request response, write-path contract |

## 4. Prerequisites

From the repository root:

```bash
cd ai-platform
npm install   # first time only
```

This slice's tests run under the workers pool and need Miniflare D1 and R2 bindings from
`wrangler.toml` (configured for prior slices).

## 5. Run the automated suite

From `ai-platform/`:

```bash
npx vitest run test/journal.test.ts --config vitest.workers.config.ts
```

Expected: **28 passing tests** (18 named test suites with parameterised cases) in
`test/journal.test.ts` for this slice only. Do **not** run `npm test` for the full platform suite.

| Test id | Describe name |
| --- | --- |
| T-C3-01 | `request_row_exists_before_provider_invoked` |
| T-C3-02 | `terminal_state_completed` |
| T-C3-03 | `terminal_state_failed` |
| T-C3-04 | `terminal_state_cancelled` |
| T-C3-05 | `guard_rejected_produces_no_row` |
| T-C3-06 | `every_state_transition_timestamped` (10 §6.3 transitions) |
| T-C3-07 | `row_survives_failed_generation` |
| T-C3-08 | `exactly_one_r2_putobject_per_request` |
| T-C3-09 | `envelope_contains_all_four_sections` |
| T-C3-10 | `one_ai_attempt_row_per_attempt` (N = 2 and 3) |
| T-C3-11 | `exactly_one_usage_event` |
| T-C3-12 | `stage16_failure_does_not_fail_request` |
| T-C3-13 | `stage16_runs_after_terminal_event` |
| T-C3-14 | `get_request_completed_returns_state_and_result` |
| T-C3-15 | `get_request_failed_returns_state_and_error_no_content` |
| T-C3-16 | `get_request_cancelled_returns_state_only` |
| T-C3-17 | `get_request_unknown_reference_returns_not_found` |
| T-C3-18 | `get_request_uses_exactly_one_indexed_query` |

## 6. Inspect the changes

Grep for the envelope key pattern in the journal module:

```bash
cd ai-platform
grep -n 'request/.*/envelope\|envelopeKey\|buildEnvelope' src/journal/index.ts
```

Grep the get-request route in the worker:

```bash
grep -n 'GET\|/v1/requests\|getRequest' src/worker.ts
```

Read the frozen contract artifact:

```bash
cat ../specs/027-journal-writer-get-request/contracts/journal.md
```

Confirm the four envelope sections (`context`, `prompt`, `attempts`, `result`), the
`GetRequestResponseBody` shape, and the stage-9/15/16 write-path timings match what
`src/journal/index.ts` exports.

After the suite runs, the test harness seeds and queries `ai_request` rows via Miniflare D1. The
fixture query pattern (from `test/journal.test.ts`) selects the columns C3 writes:

```sql
SELECT request_id, request_reference, state, created_at, updated_at,
       completed_at, terminal_error_code, payload_pointer
FROM ai_request WHERE request_id = ?;
```

List the named test suites:

```bash
grep -n '^describe(' test/journal.test.ts
```
