# Conversation evals (H4)

Frozen contracts for conversation evals as a CI-gated extension of the A9 suite
(§13.5 Conversation evals; A9): scripted multi-leg conversations against
recorded fixtures, scored **per conversation** on three criteria — right keys,
permitted set, and round-budget convergence. Later work may extend cases; it
**must not** redefine per-conversation scoring or replace F1's capability-eval
harness with a second, incompatible gate.

**Source of truth in code (this slice):**
`ai-platform/test/eval/conversation-harness.ts`,
`ai-platform/test/eval/conversation-score-report.ts`,
`ai-platform/test/eval/clinic.chat_assistant/`,
`ai-platform/test/eval/conversation.test.ts`, proven by T1–T9 and gated by the
same `.github/workflows/ci.yml` → `ai-platform-eval-golden` job as F1 goldens.

**Traces to:** spec Freezes (conversation evals as CI-gated A9 extension;
per-conversation scoring; three criteria); FR-001–FR-010; architecture §13.5
Conversation evals, A9; delivery plan §3.8 row H4, §3.11.7 row H4.

**Consumes (does not rewrite):**
- F1 `specs/039-eval-suite-harness/contracts/capability-eval-harness.md` —
  capability golden/smoke gating and quality/schema per-run recording remain
  intact.
- H2 `specs/045-transcript-validation-budgets/contracts/transcript-validation-budgets.md`,
  `transcript-wire.md`, `conversational-composition.md` — allowlist, budgets,
  transcript wire, and dual output shapes remain intact; H4 scores against them.

---

## 1. Overview

Prompts and conversational behaviour have no type system. Without conversation
evals, a change that requests the wrong keys, escapes the permitted set, or
fails to converge within the round budget can reach a clinic unnoticed (§13.5;
A9). H4 freezes **scripted multi-leg conversation cases** under the existing
eval tree, scored **per conversation**, gated in the **same CI job** as F1
capability goldens.

This harness is **CI tooling** under `ai-platform/test/eval/` only. It is not a
Worker pipeline stage, emits **no** §5.4 taxonomy codes, and adds **no**
`src/eval/` module and **no** per-request server-side state.

---

## 2. Conversation evals as a CI-gated A9 extension

### 2.1 Placement

| Element | Contract |
| --- | --- |
| Root | Sibling module under `ai-platform/test/eval/` beside F1 capability evals |
| Runtime module | **None** — no `ai-platform/src/eval/` |
| Fixture capability | One fixture conversational capability (`clinic.chat_assistant`) declaring its own round budget and permitted key set |
| Cases | Scripted multi-leg cases against that capability (required positives + negative controls) |
| CI gate | Same permanent CI job as F1 goldens (`ai-platform-eval-golden`) — not a second product |
| Fixtures | Each leg runs against **recorded fixtures** (A9 / Consumes F1); not an unbounded live chat matrix (OD-5) |

### 2.2 Active harness loop

| Rule | Contract |
| --- | --- |
| Advancement | Each leg runs against recorded fixtures; the harness appends scripted user/context turns |
| Scoring moment | The whole conversation is scored **at the end**, not turn-by-turn as the acceptance unit |
| Client surface | H3's client chat surface is **not** required; the harness owns the multi-leg loop |
| Fixture-only legs (Clarification Q1) | Conversation-eval legs append **pre-baked assistant turns** from recorded fixtures. The harness does **not** render prompts, invoke the composer, or call a provider adapter. Prompt-regression coverage for capability outputs remains F1 goldens; H4 gates H2 validator behaviour plus fixture content for the three conversation criteria. A future composer-path conversation case is out of H4 scope. |

### 2.3 What later work must not redefine

Later slices **MUST** bind to this contract for:

- Conversation evals as an extension of the F1/A9 suite (same CI gate)
- Per-conversation scoring (section 3)
- The three criteria as the H4 acceptance bar (section 4)

Capability goldens, scheduled live smoke, and F1 quality/schema score fields
remain F1's Freezes. Cohort activation after evals pass remains **J3**.

---

## 3. Per-conversation scoring (not per turn)

A conversation eval pass/fail and its recorded scores are computed over the
**whole scripted conversation**. Turn-level observations may exist inside the
harness for driving the loop; they are **not** the CI acceptance unit.

| Rule | Contract |
| --- | --- |
| Acceptance unit | Whole conversation against the three criteria |
| Failure rule | A conversation that fails a criterion on any leg **fails as a conversation** |
| Aggregation | Turn-level pass/fail **MUST NOT** be promoted to the gate |

---

## 4. The three conversation-eval criteria

Every scripted conversation under eval is scored on exactly these three
criteria (§13.5 Conversation evals; delivery plan §3.8 Done when):

| Criterion id | Meaning | Pass when |
| --- | --- | --- |
| `right_keys` | Assistant requests the *correct* key(s) the script requires | The required key request(s) occur; "any permitted key" is insufficient |
| `permitted_set` | Assistant stays inside the capability's permitted key set (§13.5) | No `context_requested` key is outside the fixture capability's `permittedKeySet`, **and** no forbidden / out-of-set key is **obtained** after H2 allowlist drop |
| `round_budget` | Conversation converges within the declared round budget | No `conversation_budget_exhausted` from H2 validation, **and** when the case declares `expect_convergence: true` the transcript's last assistant turn is `kind: "model"` |

Round budget and permitted set are taken from the fixture capability's declared
manifest fields (Consumes H2 / H1). H4 invents **no** numeric default and **no**
parallel key vocabulary.

Criteria are **independent**: a budget breach fails `round_budget` only; it does
**not** force `permitted_set` to fail. `validateContext` runs **once** per case;
scorers consume that result.

Each case declares `expected_outcome` for the three criteria. Suite `overall` /
`passed` is **pass** when every case's recorded scores **match** its
`expected_outcome` (positive and negative-control cases alike).

Outcome is **pass/fail only** — no numeric score cutoff beyond conversation
pass/fail on these three criteria (OD-10; A9; §13.5).

### 4.1 Required cases

The suite **MUST** include at least:

1. A scripted conversation that converges within the round budget
2. One case where the assistant must request the correct key
3. One case proving a key outside the permitted set cannot be obtained
4. Negative-control cases that drive each criterion to `fail` end-to-end through
   `runCase` (wrong permitted key; out-of-set request; non-convergence and/or
   budget breach) so the gate is falsifiable

---

## 5. Per-conversation score recording payload

Conversation eval scores are recorded per run so regression is measurable.
Scores are a **JSON file under `ai-platform/test/eval/`** — no new D1 table.
This payload **extends** F1 per-run recording for conversation cases; it does
**not** redefine F1's capability `quality` / `schema` case fields.

### 5.1 Payload shape

Each completed conversation-eval run **MUST** write a JSON score report with at
least:

| Field | Type | Meaning |
| --- | --- | --- |
| `capability_id` | string | Fixture conversational capability under eval (e.g. `clinic.chat_assistant`) |
| `run_kind` | `"conversation"` | Distinguishes conversation-eval reports from F1 `golden` / `live_smoke` |
| `recorded_at` | string (ISO-8601) | When the run completed |
| `conversations` | array | One entry per scripted conversation |
| `conversations[].case_id` | string | Stable case identifier |
| `conversations[].right_keys` | `"pass"` \| `"fail"` | Criterion 1 |
| `conversations[].permitted_set` | `"pass"` \| `"fail"` | Criterion 2 |
| `conversations[].round_budget` | `"pass"` \| `"fail"` | Criterion 3 |
| `conversations[].overall` | `"pass"` \| `"fail"` | Conversation overall — fail if any of the three criteria fails |
| `overall` | `"pass"` \| `"fail"` | Run overall — fail if any conversation's scores do not match its declared `expected_outcome` |

### 5.2 Recording rules

- Every conversation-eval suite run **MUST** write a report when the run
  completes.
- The three criteria are recorded **per conversation** as pass/fail.
- This contract invents **no numeric cutoff** beyond conversation pass/fail
  (A9; §13.5).
- CI **MAY** upload or retain the report as a workflow artifact; retention
  mechanics outside the JSON shape are operational, not a second freeze.

### 5.3 Example

```json
{
  "capability_id": "clinic.chat_assistant",
  "run_kind": "conversation",
  "recorded_at": "2026-08-02T00:00:00.000Z",
  "conversations": [
    {
      "case_id": "converges_within_round_budget",
      "right_keys": "pass",
      "permitted_set": "pass",
      "round_budget": "pass",
      "overall": "pass"
    }
  ],
  "overall": "pass"
}
```

---

## 6. Inherited prohibitions

| Prohibition | Contract |
| --- | --- |
| R-12 | Conversation eval fixtures and harness introduce **no** prompt text, provider name, or model identifier into Flutter client code |
| §4.4 / §9.7 | Running conversation evals introduces **no** per-request server-side state of any kind |
| §5.4 | H4 emits **no** runtime taxonomy codes; failing evals fail CI only |
| R-20 | No mechanism from §9.14 is added because it looks prudent |
