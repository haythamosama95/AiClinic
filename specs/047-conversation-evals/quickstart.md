# Quickstart: Conversation evals (H4)

H4 extends F1's CI-gated A9 eval suite with conversation evals: scripted multi-leg conversations
against recorded fixtures for one fixture conversational capability, scored per conversation on
three criteria — right keys, permitted set, and round-budget convergence — on the same CI gate as
capability goldens.

**Scope rule:** This quickstart documents **slice H4 only** — conversation eval files, tests, CI
delta, and frozen contract. It does not list prior-slice harness modules, combined test counts across
slices, or full-suite regression commands (those belong in Verification T018).

## 1. Architecture context

- **Delivery plan row H4** ([`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md) §3.8): Conversation evals after F1 and H2 — scripted multi-leg conversations scored per conversation on right keys, permitted set, and round-budget convergence.
- **Architecture sections implemented** ([`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md)):
  - §13.5 Conversation evals (A14) — for conversational capabilities, scripted multi-leg conversations against fixtures, scored per conversation rather than per turn.
  - A9 — CI-gated prompt/capability evaluation suite; H4 is a sibling extension under the same gate, not a second eval product.
- **Spec delivered** ([`spec.md`](spec.md)): FR-001–FR-010 — active multi-leg harness loop against recorded fixtures; one fixture conversational capability (`clinic.chat_assistant`) with three scripted cases; per-conversation pass/fail on `right_keys`, `permitted_set`, and `round_budget`; JSON score recording; same CI gate as F1; no Flutter prompt/provider/model strings; no per-request server-side state.
- **Plan scoped** ([`plan.md`](plan.md)): Sibling modules under `ai-platform/test/eval/` only (no `src/eval/`); `conversation-harness.ts`, `conversation-score-report.ts`, `clinic.chat_assistant/` assets, `conversation.test.ts`; extend `prohibitions.test.ts` and `ci.yml`; frozen [`contracts/conversation-evals.md`](contracts/conversation-evals.md).

## 2. What was implemented

- `ai-platform/test/eval/conversation-harness.ts` — active multi-leg loop: each leg against recorded fixtures, append scripted user/context turns, score the whole conversation at the end.
- `ai-platform/test/eval/conversation-score-report.ts` — per-conversation JSON score report for the three criteria (`right_keys`, `permitted_set`, `round_budget`); extends F1 per-run recording without redefining capability quality/schema fields.
- `ai-platform/test/eval/clinic.chat_assistant/` — one fixture conversational capability (`capability.json`) with three scripted multi-leg cases and per-leg recorded fixtures.
- `ai-platform/test/eval/conversation.test.ts` — named tests T1–T7 (convergence, correct key, permitted set, per-conversation scoring, multi-leg fixtures, F1 non-redefinition, score recording).
- `ai-platform/test/eval/prohibitions.test.ts` — extended with conversation-module coverage for T8 (no Flutter prompt/provider/model strings) and T9 (no per-request server-side state).
- `.github/workflows/ci.yml` — `ai-platform-eval-golden` job includes `conversation.test.ts` alongside golden and prohibitions entries (same CI gate as F1).
- Frozen contract: [`contracts/conversation-evals.md`](contracts/conversation-evals.md).

See [`spec.md`](spec.md) for full requirements and [`plan.md`](plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/test/eval/conversation-harness.ts` | Multi-leg loop, fixture replay, per-conversation scoring, suite runner |
| `ai-platform/test/eval/conversation-score-report.ts` | Per-conversation JSON score-report shape and writer |
| `ai-platform/test/eval/clinic.chat_assistant/capability.json` | Fixture capability manifest (round budget + permitted key set) |
| `ai-platform/test/eval/clinic.chat_assistant/cases/` | Three scripted multi-leg cases (T1–T3) |
| `ai-platform/test/eval/clinic.chat_assistant/fixtures/` | Per-leg recorded provider/assistant fixtures |
| `ai-platform/test/eval/conversation.test.ts` | Named tests T1–T7 |
| `ai-platform/test/eval/prohibitions.test.ts` | H4 conversation-module prohibitions (T8, T9) |
| `.github/workflows/ci.yml` | `ai-platform-eval-golden` job conversation entry |
| `specs/047-conversation-evals/contracts/conversation-evals.md` | Frozen conversation-eval gate, scoring, and three criteria |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/eval/conversation.test.ts test/eval/prohibitions.test.ts
```

Expected: **9 passing tests** for H4's named cases T1–T9 (7 in `conversation.test.ts`, 2
conversation-module entries in `prohibitions.test.ts`). The prohibitions file also runs two
inherited F1 structural entries in the same command — **11 passing tests** total.

To run only the conversation eval file:

```bash
npx vitest run test/eval/conversation.test.ts
```

## 5. Inspect the changes

1. Read the frozen contract:

```bash
cat specs/047-conversation-evals/contracts/conversation-evals.md
```

2. Open the conversation harness and score-report modules:

```bash
less ai-platform/test/eval/conversation-harness.ts
less ai-platform/test/eval/conversation-score-report.ts
```

3. Review the three scripted cases and per-leg fixtures:

```bash
ls ai-platform/test/eval/clinic.chat_assistant/cases/
ls ai-platform/test/eval/clinic.chat_assistant/fixtures/
```

4. After a conversation eval run, inspect a per-conversation score report:

```bash
ls ai-platform/test/eval/reports/conversation-*.json | tail -1 | xargs cat
```

5. Confirm the CI golden-eval gate includes conversation tests:

```bash
grep -A3 "Run golden eval suite" .github/workflows/ci.yml
```
