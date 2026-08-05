# Contract: Conversational manifest fields (H1)

**Frozen by:** Slice H1 — Conversational manifest fields and context-request schema
**Implements:** §5.1 Interaction + Context requirements rows, §5.7 Interaction mode row, A14 of
`docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices (H2, H3) **consume** this artifact; they extend, never rewrite
these field keys, load rules, or the interaction-mode versioning rule (delivery plan §2.3).

**Source of truth in code:** `ai-platform/src/manifest/index.ts` (conversational load / reject
branches on `load`).

**Traces to:** spec **Freezes** (conversational Interaction fields; permitted key set; interaction
mode fixed for the life of a capability version); FR-001–FR-006.

**Extends (does not rewrite):** `specs/018-ai-capability-manifest/contracts/manifest-schema.md` (A4)
— ten field groups, omitted-`interactionMode` → `single_shot` default, and the rule that
conversational-only fields are rejected on `single_shot`.

---

## 1. Overview

When a capability declares `interactionMode: "conversational"`, the A4 loader must accept only
manifests that carry the four conversational extras. Those extras are unreachable for
`single_shot` (including when `interactionMode` is omitted and defaults). Changing
`interactionMode` on a published version is a new capability version, never an in-place edit.

---

## 2. Conversational Interaction fields

Present on the **Interaction** group when `interactionMode` is `conversational`. All three are
required; omitting any fails `load()` naming the omission. There is no silent default.

| Field key (wire, camelCase) | Type / range | Contents |
| --- | --- | --- |
| `maxHistoryTurns` | Finite positive integer (`number`, `Number.isInteger`, `> 0`) | Maximum transcript history turns for this capability version. |
| `maxContextRoundsPerTurn` | Finite positive integer (`number`, `Number.isInteger`, `> 0`) | Maximum consecutive context-negotiation rounds per turn. |
| `transcriptSizeLimit` | Finite positive integer (`number`, `Number.isInteger`, `> 0`) | Maximum transcript size bound for this capability version. |

Wrong type, non-finite, non-integer, negative, or zero values fail `load()` as malformed
conversational Interaction fields.

Concrete numeric product ceilings are Open Decisions 12/13 at capability authoring time — H1
freezes that the fields exist and validate as finite positive integers, not their product
defaults.

**Consumed by:** Protocol adapter, context validator, prompt composer (later H2/H3).

---

## 3. Permitted key set (Context-requirements form)

For `interactionMode: "conversational"`, the **Context requirements** group is **not** the A4
ordered array of `{key, required, shapeRef, maxSize, freshnessHint}` entries. It is the permitted
key set form:

```json
{
  "permittedKeySet": ["visit.chief_complaint@v1", "patient.demographics@v1"]
}
```

| Field key | Type | Rules |
| --- | --- | --- |
| `permittedKeySet` | `string[]` | Required when mode is `conversational`. Each element MUST be a key known to the platform's published context-key vocabulary (A5 `validateKey`). An unknown key fails `load()`. **Empty array is legal** (allowlist of zero — the capability may never request context keys). **Duplicate keys are rejected.** |

Omitting `permittedKeySet` on a conversational manifest fails the build naming that omission.

**Consumed by:** Context validator allowlist enforcement (H2); client Context Resolver (H3).

---

## 4. Rejection on `single_shot`

When `interactionMode` is `single_shot` (explicit or defaulted), `load()` MUST reject a manifest that
carries any of:

- `maxHistoryTurns`
- `maxContextRoundsPerTurn`
- `transcriptSizeLimit`
- `permittedKeySet` (or a Context-requirements value in the conversational object form)

There is no silent-stripping path (A14; A4 Freezes extended, not rewritten).

---

## 5. Interaction mode fixed for the life of a version

| Rule | Enforcement |
| --- | --- |
| `Manifest.interactionMode` is immutable for a loaded version | Read-only at the type / loader surface (A4); assignment does not mutate. |
| Changing `single_shot` ↔ `conversational` on a published version | New capability version; in-place content-hash change fails `verifyPublishedRegistry` (build). |

---

## 6. Out of scope of this contract

- Transcript validation, budget counting, `conversation_budget_exhausted` (H2).
- Journaling `conversation_id` / `turn_ordinal` write behaviour beyond what C3 already allows (H3).
- Choosing a chat capability's concrete permitted keys or numeric limits (Open Decisions 12, 13).
