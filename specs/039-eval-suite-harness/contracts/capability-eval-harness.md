# Capability eval harness (F1)

Frozen contracts for the prompt/capability evaluation suite (A9 / §13.5): how
golden cases gate CI against recorded provider fixtures, how a deliberately
regressed prompt fails that gate, how the smaller live smoke set is scheduled
against pinned model versions, and the per-run JSON score-report payload.
Later slices **D7** (capability-eval clause), **H4** (conversation evals), and
**J3** (staged rollout after evals pass) **consume** this artifact — they must
not redefine how golden cases gate CI, how live smoke is scheduled against
pinned models, or how scores are recorded.

**Source of truth in code (this slice):**
`ai-platform/test/eval/` (harness, cases, expectations, score report, Vitest
entries), proven by `golden.test.ts`, `live-smoke.test.ts`, and
`prohibitions.test.ts`, gated by `.github/workflows/ci.yml` and scheduled by
`.github/workflows/ai-platform-eval-live-smoke.yml`.

**Traces to:** spec Freezes (capability eval harness; CI regression gate;
per-run score recording); FR-001–FR-010; architecture §13.5 Capability evals
(A9), A9; delivery plan §3.7 row F1, §3.11.6 row F1.

---

## 1. Overview

Prompts are the platform's core logic and have no type system. Without
regression evals, every prompt edit is an unreviewable change (A9). F1 freezes
a **CI-gated golden suite** per capability against recorded provider fixtures,
plus a **smaller scheduled live smoke** against pinned model versions, with
**scores recorded per run** so regression is measurable.

This harness is **CI / scheduled tooling** under `ai-platform/test/eval/` only.
It is not a Worker pipeline stage, emits **no** §5.4 taxonomy codes, and adds
**no** `src/eval/` module.

---

## 2. Capability eval harness (A9)

### 2.1 Placement

| Element | Contract |
| --- | --- |
| Root | `ai-platform/test/eval/` only |
| Runtime module | **None** — no `ai-platform/src/eval/` |
| First capability | `clinic.visit_summary` (D1 fixture capability; OD-1 recommended default) |
| Scope | Per capability — the harness does not require a cross-capability aggregate gate |
| Consumes | D1 pinned prompt artifacts + composer output; D5 recorded fixtures behind the D2 provider port — unchanged |

### 2.2 Golden cases (CI)

| Rule | Contract |
| --- | --- |
| Gate | Golden cases for the capability under eval **MUST** run in CI on every change that joins the permanent suite (delivery plan §3.10) |
| Fixtures | Golden cases **MUST** run against **recorded provider fixtures**, not live provider egress as the permanent regression gate (§13.5; Consumes D5) |
| What is tested | Output **quality** and **schema conformance** per capability (§13.5) |
| Quality assertion | Per-case golden expectations under `test/eval/` — structured checks and/or expected-output fixtures |
| Schema assertion | Schema validation of the fixture-backed result |
| Outcome | **Pass/fail only** — no numeric score cutoff is part of this contract |
| Current prompt | The golden set **MUST** pass on the current pinned production prompt artifact for the first capability |

### 2.3 Live smoke (scheduled)

| Rule | Contract |
| --- | --- |
| Trigger | GitHub Actions **scheduled** workflow runs the live-smoke Vitest entry |
| Harness | Same `test/eval/` harness as CI goldens (separate Vitest entry) |
| Models | Smoke **MUST** target **pinned model versions** from routing policy (never floating aliases) |
| Role | Smaller set that catches silent model drift; **not** a substitute for the CI golden gate; **not** an unbounded live matrix (OD-5) |

### 2.4 What later slices must not redefine

D7, H4, and J3 **MUST** bind to this harness for:

- How golden cases gate CI against recorded fixtures
- How live smoke is scheduled against pinned models
- How per-run scores are recorded (section 4)

Conversation-scored multi-leg evals remain **H4**. Cohort activation after
evals pass remains **J3**. F1 does not rework D7's adapter or policy
registration.

---

## 3. CI regression gate for prompt changes

Prompt artifacts remain immutable D1-owned assets deployed with the Worker.
Swapping a prompt is a new capability **build**, guarded by this suite
(Consumes D1; A9).

| Rule | Contract |
| --- | --- |
| Happy path | Current pinned prompt → golden set **passes** → change is allowed |
| Regression path | Deliberately worse prompt artifact (checked in under `ai-platform/test/eval/`, separate from production pinned prompts) → golden set **fails** → change is **blocked** in CI |
| Soft fail | **None** — A9 / §13.5 name no warn-only mode |
| Production prompts | The worse artifact **MUST NOT** replace or mutate production files under `ai-platform/prompts/` |

---

## 4. Per-run score recording contract

Eval scores are recorded per run so regression is measurable across CI golden
and scheduled smoke executions. Scores are a **JSON file under
`ai-platform/test/eval/`** — no new D1 table.

### 4.1 Payload shape

Each completed run **MUST** write a JSON score report with at least:

| Field | Type | Meaning |
| --- | --- | --- |
| `capability_id` | string | Capability under eval (e.g. `clinic.visit_summary`) |
| `run_kind` | `"golden"` \| `"live_smoke"` | Which entry produced the report |
| `prompt_build` | `"current"` \| `"deliberately_regressed"` | Which prompt build was evaluated |
| `recorded_at` | string (ISO-8601) | When the run completed |
| `cases` | array | One entry per case |
| `cases[].case_id` | string | Stable case identifier |
| `cases[].quality` | `"pass"` \| `"fail"` | Output-quality outcome for the case |
| `cases[].schema` | `"pass"` \| `"fail"` | Schema-conformance outcome for the case |
| `overall` | `"pass"` \| `"fail"` | Run overall — fail if any required case fails quality or schema |

### 4.2 Recording rules

- Every eval suite run (CI golden or scheduled smoke) **MUST** write a report
  when the run completes.
- Quality and schema are recorded **per case** as pass/fail.
- This contract invents **no numeric cutoff** beyond the golden pass/fail gate
  (A9; §13.5).
- CI/smoke **MAY** upload or retain the report as a workflow artifact; retention
  mechanics outside the JSON shape are operational, not a second freeze.

### 4.3 Example

```json
{
  "capability_id": "clinic.visit_summary",
  "run_kind": "golden",
  "prompt_build": "current",
  "recorded_at": "2026-08-02T00:00:00.000Z",
  "cases": [
    {
      "case_id": "visit_summary.happy_path",
      "quality": "pass",
      "schema": "pass"
    }
  ],
  "overall": "pass"
}
```

---

## 5. Inherited prohibitions (harness)

The harness **MUST NOT**:

- Put prompt text, provider names, or model identifiers into Flutter client code (R-12)
- Introduce per-request server-side state of any kind (§4.4, §9.7)
- Add a second Quota Durable Object round trip or a second R2 object per request (§7.5, §13.6)
- Journal a guard rejection as a request or write a D1 row per stream chunk (§7.5)
- Pull forward any §9.14 mechanism because it looks prudent (R-20)
- Emit runtime §5.4 taxonomy codes — golden failure fails CI; it does not invent a request error code

---

## 6. Out of this freeze

- D1 registry/composer pin and composition rules (already frozen; Consumes)
- D5 adapter wire mapping and fixture-suite duties (already frozen; Consumes)
- D6 pipeline validation/repair
- D7 second adapter and policy registration (eval clause consumes this harness)
- F2 acceptance recording; H4 conversation evals; J3 canary cohorts
- OD-10 clinical reviewer workflow (suite half only)
