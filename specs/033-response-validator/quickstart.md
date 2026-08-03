# Quickstart: Response validator, bounded repair, and structured output modes (D6)

Slice D6 adds ordered response validation (transport/parse → schema → business constraints → safety guards), bounded repair via an injected `reask` port when the manifest allows it, and `structured` / `structured_atomic` streaming emission under commit-time validation — provisional `partial_structured` vs progress/heartbeat only, with a self-contained validated terminal payload.

**Scope rule:** This quickstart documents **this slice only**. It lists only files D6 added or modified, only D6 test files, and only commands that run D6 tests.

## 1. Architecture context

- **Delivery plan row D6** ([`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md) §3.5): response validator, bounded repair, and structured output modes in band D.
- **Architecture sections implemented** ([`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md)):
  - §4.3.9 — ordered validation phases, safety guards, bounded repair (policy-gated re-ask, cap/count/journal, `validation_failed`, no invalid content returned)
  - §6.4 — `structured` (`partial_structured` provisional) and `structured_atomic` (progress/heartbeat only); authoritative self-contained terminal payload; provisional never committed at emission
  - §5.1 — Output field group consumed from manifest (mode, schema ref, business rule refs, repair policy)
- **Spec delivered** ([`spec.md`](spec.md)): frozen phase order, bounded repair contract, and structured / `structured_atomic` streaming rows; twenty-four named unit (ordering) + integration tests (T-D6-01..T-D6-24).
- **Plan scoped** ([`plan.md`](plan.md)): new `ai-platform/src/validate/` (phases + repair orchestration); extended `ai-platform/src/stream/index.ts` for structured emission; two test files; frozen contract in `contracts/response-validator.md`; in-memory schema/rule registries and injected `reask` in tests; consumes D4 stream broker unchanged for prose/cancel duties; no D1 migrations or `wrangler.toml` edits.

## 2. What was implemented

- `ai-platform/src/validate/phases.ts` — ordered validation: transport/parse → schema conformance (in-memory registry) → declared business-constraint checks → safety guards (leaked instructions, refusals, empty, truncated, injection echo).
- `ai-platform/src/validate/index.ts` — orchestrates phases; reads manifest Output fields; invokes injected `reask(errors)` within `repairPolicy.maxAttempts`; journals attempts and counts repair cost via injectable sinks; fails with `validation_failed` when repair is disallowed or exhausted; never returns invalid content; no per-request server-side state.
- Extended `ai-platform/src/stream/index.ts` — `structured` emits provisional `partial_structured` events; `structured_atomic` emits progress/heartbeat only; at completion validates via `validate/` and emits one `completed` carrying the whole self-contained validated document; D4 `prose` relay, guards, heartbeat, and cancel paths unchanged.
- Frozen contract: [`contracts/response-validator.md`](contracts/response-validator.md) — phase order, bounded repair, structured emission invariants, prohibitions.

See [`spec.md`](spec.md) for full requirements and [`plan.md`](plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/validate/phases.ts` | Four ordered validation phases |
| `ai-platform/src/validate/index.ts` | Validate + bounded repair orchestration with `reask` port |
| `ai-platform/src/stream/index.ts` | Extended for `structured` / `structured_atomic` emission |
| `ai-platform/test/response-validator.test.ts` | T-D6-01..T-D6-16 (validator + repair) |
| `ai-platform/test/structured-modes.test.ts` | T-D6-17..T-D6-24 (structured emission + prohibitions) |
| `specs/033-response-validator/contracts/response-validator.md` | Frozen phase order, repair, and structured-mode contract |

## 4. Prerequisites

From the repository root, first time only:

```bash
cd ai-platform
npm install
```

D6 tests are CPU-only — no Miniflare bindings or live provider required for this slice's suite.

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run test/response-validator.test.ts test/structured-modes.test.ts
```

Expected: **30 passing tests** for this slice only (`response-validator.test.ts` — T-D6-01..T-D6-16; `structured-modes.test.ts` — T-D6-17..T-D6-24).

To run a subset of this slice's tests:

```bash
npx vitest run test/response-validator.test.ts
npx vitest run test/structured-modes.test.ts
```

## 6. Inspect the changes

Read the frozen contract:

```bash
cat specs/033-response-validator/contracts/response-validator.md
```

Inspect validation phases, repair port, and structured emission:

```bash
grep -n 'runValidationPhases\|validateAndRepair\|partial_structured\|structured_atomic' ai-platform/src/validate/ ai-platform/src/stream/index.ts
```

Run the focused test files:

```bash
cd ai-platform
npx vitest run test/response-validator.test.ts test/structured-modes.test.ts
```
