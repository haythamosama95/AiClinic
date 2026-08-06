# Contract: Platform-owned context-request schema (H1)

**Frozen by:** Slice H1 — Conversational manifest fields and context-request schema
**Implements:** §6.7.2 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices (H2 composer/validator, H3 client negotiation) **consume** this
artifact; they may not introduce a per-capability alternate shape (delivery plan §2.3).

**Source of truth in code:** `ai-platform/src/context/context-request.ts`
(`validateContextRequest` and exported types).

**Traces to:** spec **Freezes** (platform-owned context-request schema); FR-007, FR-011.

---

## 1. Overview

A conversational turn may end by asking the client for clinic data. That ask is structured output
validated against **one platform-owned schema shared by every conversational capability** — a list
of `{key, arguments}` drawn from the manifest's permitted set. It is not a per-capability schema.

Runtime allowlist enforcement against the manifest's permitted set, and offering this schema as a
second composer output shape alongside prose, belong to H2. H1 freezes the shared shape and its
malformed-form rejections only.

---

## 2. Wire shape

A conforming context request is a JSON **array**. Each element is a plain object with exactly the
semantic fields below (additional properties are out of scope for H1 acceptance; validators MAY
ignore or reject extras consistently — H1's named malformed forms do not include "extra property").

```json
[
  { "key": "visit.chief_complaint@v1", "arguments": { "visit_id": "…" } },
  { "key": "patient.demographics@v1", "arguments": {} }
]
```

| Field | Type | Rules |
| --- | --- | --- |
| (root) | `array` | Must be a list. A non-list root is rejected. |
| `key` | `string` | Required on each element. Names a context key. |
| `arguments` | `object` | Required on each element. May be empty. Carries resolver arguments for that key. |

An element that is not a plain `{key, arguments}` object is rejected. An element missing `key` or
missing `arguments` is rejected.

---

## 3. Platform ownership

| Invariant | Meaning |
| --- | --- |
| One schema | Every conversational capability shares this shape. |
| Not per-capability | The validator MUST NOT accept an alternate capability-authored request schema in place of this list. |
| No new pipeline stage | Declaring `conversational` does not add a §6.1 stage; stage 13 later gains a second valid output shape parameterized by the manifest (H2). |

---

## 4. Relationship to the permitted key set

At runtime (H2), each `key` in a validated request must be drawn from the capability's permitted
key set. H1's shared schema validates **structure** only; key membership against a concrete
manifest is not this contract's accept/reject table.

---

## 5. Out of scope of this contract

- Allowlist drop of keys outside the permitted set (H2).
- Composer rendering / second output-shape wiring (H2).
- Client resolution of requested keys (H3).
- `conversation_budget_exhausted` and transcript bounds (H2).
