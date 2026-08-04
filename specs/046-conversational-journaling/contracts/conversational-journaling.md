# Contract: Conversational journaling (H3)

**Frozen by:** Slice H3 — Conversational journaling and client chat surface  
**Implements:** §7.3, §6.7.1, §6.7.2, §8.10 of `docs/architecture/17-ai-platform.md`  
**Status:** Frozen. Later slices (support conversation reads, conversation evals) **consume** this
artifact; they may extend it and may not rewrite the column-population rule, the ordered
conversation query, independent per-leg accountability, or the no-conversation-entity rule
(delivery plan §2.3).

**Source of truth in code (this slice):** `ai-platform/src/journal/index.ts`
(`createRequestRow` conversational column write; `listConversationLegs` ordered query).

**Traces to:** spec **Freezes** (writing `conversation_id` / `turn_ordinal`; one indexed query;
each leg independently admitted/journaled/credited; no conversation entity / no per-request
server-side state); FR-001–FR-007, FR-015.

**Consumes (not redefined here):** C3 journal lifecycle and one-envelope rule
(`specs/027-journal-writer-get-request/contracts/journal.md`); A5 nullable columns
(`specs/019-ai-context-keys-d1-config/data-model.md`); H1 `AwaitingContext` /
`context_requested` terminal contracts.

---

## 1. Overview

A conversation is not a session the platform holds. It is a series of independent requests through
the same §6.1 pipeline, tied together only by two client-supplied fields written on each
conversational leg's ordinary `ai_request` row. There is no `conversation` table and no
per-request server-side state object.

---

## 2. Column population on `ai_request`

| Field | Supplied by | Written when | Nullable otherwise |
| --- | --- | --- | --- |
| `conversation_id` | Client, once per chat | Every conversational leg of that chat | Yes — `NULL` for `interaction_mode: single_shot` and when absent |
| `turn_ordinal` | Client, incremented per leg | Every conversational leg | Yes — same |

Rules:

- Both fields are written on the ordinary stage-9 `ai_request` row (C3 `createRequestRow`).
- This slice does **not** add a schema migration for the columns (reserved in A5).
- `single_shot` legs MUST continue to write `NULL` for both columns (C3 behaviour preserved).

---

## 3. One ordered conversation query

Support and evals read a conversation as a unit with **one** D1 query:

```sql
SELECT …
FROM ai_request
WHERE conversation_id = ?
ORDER BY turn_ordinal;
```

| Property | Rule |
| --- | --- |
| Grouping | All legs sharing the supplied `conversation_id` |
| Order | Ascending `turn_ordinal` |
| Entity | Ordinary `ai_request` rows only — no join to a conversation table |
| Helper | `listConversationLegs(conversationId)` (or equivalent) in `src/journal/` exposes this query |

A5 documents this query pattern; H3 freezes the behavioural contract that the journal returns the
whole conversation ordered through that single query.

---

## 4. Independent per-leg accountability

| Invariant | Meaning |
| --- | --- |
| One row per leg | N legs → N `ai_request` rows |
| One admission per leg | N legs → N Quota DO admissions; no shared conversation counter |
| One credit per leg | N legs → N usage credits |
| `context_requested` credit | A leg that terminates as `context_requested` / reaches `AwaitingContext` is credited with **actual** usage because the inference happened |
| Idempotency | Each leg carries its own idempotency key (client); transport retry returns that leg |

---

## 5. What must not exist

| Prohibition | Rule |
| --- | --- |
| No `conversation` table / entity | Conversations add two nullable columns and no table (§7.3) |
| No per-request server-side state | After leg *n* terminals and before leg *n+1* submits, the platform holds no conversation state between them (§6.7.1; §6.7.4) |
| No second R2 object from H3 | Exactly one R2 envelope per leg remains C3's rule (§7.4.1) |
| No second Quota DO round trip from H3 | Per-leg budget remains one admission + one credit (§7.5; §13.6) |
| No new pipeline stage | A leg traverses §6.1 unchanged (§6.7.4) |

---

## 6. Out of scope of this contract

- Flutter Conversation store and chat negotiation loop (client Freezes; bind to
  `frontend/lib/core/ai/conversation_*.dart`).
- Transcript wire-shape validation and conversation budgets (H2).
- Conversation evals scoring (H4).
- Rewriting C3 get-request, envelope layout, or stage-16 post-response detail.
