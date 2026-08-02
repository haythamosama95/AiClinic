# Quickstart: Transcript validation, conversation budgets, and composer rendering (H2)

H2 extends the context validator, prompt composer, and response validator so conversational
capabilities validate client-supplied transcripts, enforce transcript-local budgets, render prior
turns as delimited typed data, and accept either prose or a platform-owned context request as output.

## 1. Architecture context

- **Delivery plan row:** [§3.8 band H — H2](../../docs/architecture/17b-ai-platform-delivery-plan.md)
  (Transcript validation, conversation budgets, and composer rendering).
- **Architecture sections:** `17-ai-platform.md` §4.3.5 (context validator), §6.7.1 (transcript wire
  shape), §6.7.3 (conversation budgets), §4.3.6 (composer), §6.7.2 (dual output shapes).
- **Spec delivered:** Closed transcript wire validation (whole accept-or-reject, shape before
  budgets), `conversation_budget_exhausted` for budget breaches, permitted-key allowlist drops,
  prior-turn rendering with closed role tags, and dual prose / context-request output acceptance —
  with no conversation store or per-request server state.
- **Plan scoped:** Three modified source surfaces (`validator.ts`, `composer.ts`, `validate/`), three
  new test files, three frozen contracts, and this quickstart — no D1 migration, no Flutter/backend
  changes.

## 2. What was implemented

- Conversational transcript shape/order validation, shape-before-budgets ordering, history-turn and
  context-round budgets, and permitted-key allowlist in `ai-platform/src/context/validator.ts`.
- Prior-turn rendering with closed role tags (`user` / `assistant` / `data`) and a second
  permitted output-shape offer in `ai-platform/src/prompt/composer.ts`.
- Dual-shape acceptance (prose **or** platform context-request schema) in
  `ai-platform/src/validate/phases.ts` and `ai-platform/src/validate/index.ts`.
- Frozen contracts under `specs/045-transcript-validation-budgets/contracts/`.
- See [spec.md](./spec.md) for full requirements and [plan.md](./plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/context/validator.ts` | Conversational transcript validation, budgets, allowlist |
| `ai-platform/src/prompt/composer.ts` | Prior-turn rendering and dual output-shape offer |
| `ai-platform/src/validate/phases.ts` | Dual-shape acceptance in validation phases |
| `ai-platform/src/validate/index.ts` | Wires conversational dual-shape into `validateAndRepair` |
| `ai-platform/test/transcript-validation.test.ts` | Transcript shape/order/budget/allowlist unit tests |
| `ai-platform/test/conversational-composer.test.ts` | Composer golden and R-10 tests |
| `ai-platform/test/conversational-response-validator.test.ts` | Dual output-shape unit tests |
| `specs/045-transcript-validation-budgets/contracts/transcript-wire.md` | Frozen closed transcript wire shape |
| `specs/045-transcript-validation-budgets/contracts/transcript-validation-budgets.md` | Frozen validation order, budgets, allowlist |
| `specs/045-transcript-validation-budgets/contracts/conversational-composition.md` | Frozen role-tag rendering and dual output shapes |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/transcript-validation.test.ts test/conversational-composer.test.ts test/conversational-response-validator.test.ts
```

Expected: **28 passing tests** across the three H2 test files.

To run a single file:

```bash
npx vitest run test/transcript-validation.test.ts
```

## 5. Inspect the changes

1. Read the three frozen contracts in `specs/045-transcript-validation-budgets/contracts/`.
2. Open `ai-platform/src/context/validator.ts` — search for `validateConversationalContext` and
   `conversation_budget_exhausted`.
3. Open `ai-platform/src/prompt/composer.ts` — search for `renderTranscriptPriorTurns` and
   `CONTEXT_REQUEST_SCHEMA_ID`.
4. Open `ai-platform/src/validate/phases.ts` — search for `tryParseContextRequest`.
5. Run the focused test files from §4 to confirm the passing state.
