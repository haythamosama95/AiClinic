# Contract: Closed transcript wire shape (H2)

**Frozen by:** Slice H2 — Transcript validation, conversation budgets, and composer rendering
**Implements:** §6.7.1 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices (H3 journaling/client chat, H4 conversation evals) **consume** this
artifact; they may not redefine how a turn is spelled (delivery plan §2.3).

**Source of truth in code:** `ai-platform/src/context/validator.ts` (conversational transcript
validation against this table).

**Traces to:** spec **Freezes** (closed, platform-owned transcript wire shape); FR-002, FR-003,
FR-004, FR-005, FR-006.

**Extends (does not rewrite):** C2 context-validator contract
(`specs/026-context-validator-cost-preflight/contracts/context-validator.md`) — stage-6 remains the
owner of context payload filtering for `single_shot`; H2 adds conversational transcript validation
on the same stage.

---

## 1. Overview

Each conversational leg carries the **transcript so far** as a JSON array of turn objects on the
submit surface. The wire shape is closed and platform-owned: a capability may choose what its
assistant talks about, never how a turn is spelled. The platform reads the transcript, uses it, and
forgets it — no conversation store (FR-002; §6.7.1).

---

## 2. Submit field

| Field | Type | Rules |
| --- | --- | --- |
| `transcript` | JSON array of turn objects | Required for conversational legs that supply prior turns; validated whole. Untrusted in the same sense as any context payload. |

The leg also carries its own `turn_ordinal` (client-incremented per leg). Every transcript
`turn_ordinal` MUST be strictly less than the leg's own value (FR-004; §6.7.1).

---

## 3. Common turn fields

Every turn declares exactly these two common fields, plus the one payload field its `kind` defines:

| Field | Type | Rules |
| --- | --- | --- |
| `turn_ordinal` | `integer` | Required. Strictly increasing across the array, no duplicates, every value strictly less than the leg's own `turn_ordinal`. Gaps are legal (client may trim; R-22). |
| `kind` | `string` | Required. One of the four kinds below. No other value is accepted. |

---

## 4. Kind → payload table

| `kind` | Payload field | Payload type | Meaning |
| --- | --- | --- | --- |
| `user` | `text` | `string` | What the clinician typed. |
| `model` | `text` | `string` | A prior validated prose answer. |
| `context_requested` | `requests` | `array` | The platform-owned `{key, arguments}` list emitted on that turn, verbatim. |
| `context_resolved` | `context` | `object` | Keys the client resolved, keyed and shaped as an ordinary context payload. |

A turn MUST carry exactly the payload field its `kind` defines — no missing field, no wrong field,
no wrong type, no unknown `kind`.

---

## 5. Malformed turn → `context_invalid`

A turn is malformed when any of the following hold:

- missing or non-integer `turn_ordinal`
- `turn_ordinal` that does not respect the ordering rule (not strictly increasing, duplicate, or not
  strictly less than the leg's own)
- unknown `kind`
- no payload field, wrong payload field for `kind`, or payload of the wrong type

Malformed turns are rejected with taxonomy code `context_invalid` (422, not retryable, no quota;
client remedy "bug: report with request reference"). No new taxonomy code is introduced (FR-005;
§5.4).

---

## 6. Whole-transcript accept-or-reject

There is no coercion and no silent drop of a bad turn. A transcript is accepted whole or rejected
whole. The allowlist **drop** rule applies only to keys *inside* a `context_resolved` turn's
`context` object (and ordinary permitted-key filtering) — never to discarding a malformed turn
(FR-006).

---

## 7. Out of scope of this contract

- Budget counting and `conversation_budget_exhausted` — see `transcript-validation-budgets.md`.
- Composer role-tag rendering — see `conversational-composition.md`.
- Journaling `conversation_id` / `turn_ordinal` and the Flutter chat surface — H3.
