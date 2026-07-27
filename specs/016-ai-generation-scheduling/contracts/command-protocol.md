# Command Protocol Envelope Contract (Phase 2 / feature 016)

**Spec**: `specs/016-ai-generation-scheduling/spec.md` (§9.1, §10.1)
**Applies to**: `POST /v1/ai/generate` responses where `task="command"` (the scheduling agent
in this phase). The single-command envelope is defined as a length-1 plan; clients MUST treat it
so. The `task:"plan"` multi-command form is reserved and not emitted this phase.

This contract is the source of truth for the wire shape. Schema implementations in code
(`validation/envelope.py`, `agents/scheduling/schemas.py`) are validated against this document
by contract tests.

---

## 1. Envelope — single command (`task:"command"`)

```json
{
  "schema_version": "1.0",
  "task": "command",
  "command_type": "create_appointment",
  "confidence": 0.92,
  "display_summary": "Book Ahmed Hassan with Dr. Ali tomorrow at 5:00 PM",
  "params": {
    "patient_name": "Ahmed Hassan",
    "doctor_name": "Dr. Ali",
    "date": "2026-05-14",
    "time": "17:00",
    "type": "planned"
  },
  "requires_resolution": {
    "patient_id": "lookup_required",
    "doctor_id": "lookup_required"
  },
  "warnings": [],
  "needs_clarification": false
}
```

### 1.1 Field semantics

| Field                  | Type                                  | Required | Always present | Notes                                                                |
| ---------------------- | ------------------------------------- | -------- | -------------- | -------------------------------------------------------------------- |
| `schema_version`       | string                                | yes      | yes            | `"1.0"` this phase; bumped only on breaking-change path `/v2` (spec §10.5). |
| `task`                 | `"command"` \| `"plan"` \| `"text"` \| `"clinical_note"` \| `"analytics"` | yes | yes | In-scope this phase: `"command"`. `"plan"` is reserved (not emitted). |
| `command_type`         | enum (scheduling catalog below)       | yes      | yes            | One of the four registered scheduling command types.                |
| `confidence`           | float in `[0,1]`                     | yes      | yes            | Raw model output; carried even when `needs_clarification=true`.     |
| `display_summary`      | string                                | yes      | yes            | Human-readable, non-actionable sentence for the future approval card. The semantic validator asserts it is consistent with `params` (referenced names appear in `params` or `requires_resolution`). |
| `params`               | object matching the command schema     | yes      | yes            | See `scheduling-schema.md`. Entity **id** fields MUST NOT be fabricated by the AI; only names the client can resolve appear. |
| `requires_resolution`  | object `dict<field-name, "lookup_required">` | yes | yes   | Bare-string form only this phase. The structured-directive form is reserved (§9.1); clients MUST handle it conservatively when introduced later (this phase emits the string form only). |
| `warnings`             | list of `Warning`                     | yes      | yes            | Empty list when no warnings.                                         |
| `needs_clarification`  | bool                                  | yes      | yes            | Set by the Gateway: `true` when `confidence < ai.confidence_threshold` (default `0.6`); destructively forced `true` for destructive command types (`cancel_appointment`, `reschedule_appointment`, and `update_appointment_status` when `status="cancelled"`) when any resolved field is ambiguous (per /clarify Q1). |

### 1.2 `Warning` object

```json
{ "code": "ambiguous_ref", "message": "Multiple doctors named \"Ali\" found; needs human disambiguation." }
```

| Field     | Type   | Notes                                            |
| --------- | ------ | ------------------------------------------------ |
| `code`    | string | Stable machine-readable code.                    |
| `message` | string | Human-readable explanation (may be shown to users). |

### 1.3 `requires_resolution` directive — current and reserved forms

**Current form (V2, this phase)** — bare string:
```json
"requires_resolution": { "patient_id": "lookup_required", "doctor_id": "lookup_required" }
```

**Reserved form (future, additive)** — structured directive:
```json
"requires_resolution": {
  "doctor_id": { "lookup": "doctor", "hint": "Ali", "then": "available_slots" }
}
```

Clients MUST accept the bare-string form. Clients MUST treat an unrecognized structured directive
conservatively (surface for manual resolution rather than guessing). V2 emits the bare-string
form only.

---

## 2. Reserved `task:"plan"` form (not emitted this phase)

When `enable_multi_command_plans=false` (default), the Gateway MUST NOT emit `task:"plan"`. When
the flag later becomes enabled and the client sets `options.plan_mode="multi"`, a plan response
carries a top-level `display_summary` and a `commands` array whose elements **each** match the
single-command envelope above (minus `schema_version`/`task`, which are top-level):

```json
{
  "schema_version": "1.0",
  "task": "plan",
  "display_summary": "...",
  "commands": [
    {
      "command_type": "create_appointment",
      "confidence": 0.91,
      "display_summary": "...",
      "params": { ... },
      "requires_resolution": { ... },
      "warnings": [],
      "needs_clarification": false
    }
  ]
}
```

Single-command responses are a length-1 plan semantically; the wire form this phase remains the
single-command envelope in §1.

---

## 3. Non-command responses (reserved; not emitted by the scheduling agent this phase)

For `task:"text"` and `task:"clinical_note"` (later phases) the envelope carries `content`
(instead of `command_type`/`params`). For `task:"analytics"` it carries `query_id` +
`query_params`. None are emitted by the scheduling agent.

---

## 4. Versioning and compatibility (spec §10.5)

- The Gateway API is versioned by path (`/v1`) **and** payloads carry `schema_version`.
- Additive changes (new optional fields, new `command_type`, new `task`) MUST NOT bump the path
  version. Breaking changes introduce `/v2` and are served alongside `/v1` over a deprecation
  window.
- Clients MUST ignore unknown fields (forward-compat).
- The following growth paths are explicitly reserved additive and MUST NOT require a path-version
  bump when introduced: multi-command `task:"plan"` responses, structured
  `requires_resolution` directives, `conversation_id`/`turn` multi-turn continuation, and
  Gateway-internal agentic tool loops.

---

## 5. Test assertions (what contract tests MUST verify)

- Every scheduling `command_type` produces an envelope that validates against §1.
- `command_type` is always one of the four scheduling commands (off-catalog impossible).
- `confidence` is in `[0,1]`; `display_summary` is present and consistent with `params`; `warnings`
  is a list; `needs_clarification` is a boolean.
- `requires_resolution` is the bare-string form this phase; clients tolerate structured
  directives (test by injecting a structured directive and asserting the client surfaces manual
  resolution — exercised later in Phase 3).
- For the same input, non-streaming `200` body and the streaming `final` SSE event are equivalent
  (SC-002).
- Adversarial prompts cannot alter `command_type` outside the catalog (SC-004).
- Below `ai.confidence_threshold`, `needs_clarification=true` (SC-001 + /clarify Q1).
- Destructive commands with ambiguous resolved fields have `needs_clarification=true`
  regardless of raw confidence.