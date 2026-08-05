# Contract: Conversational composition and dual output shapes (H2)

**Frozen by:** Slice H2 — Transcript validation, conversation budgets, and composer rendering
**Implements:** §4.3.6, §6.7.2 of `docs/architecture/17-ai-platform.md`
**Status:** Frozen. Later slices (H3 client chat, H4 evals) **consume** this artifact; they may not
rewrite role-tag mapping, R-10 delimited opacity, or the dual permitted output shapes (delivery plan
§2.3).

**Source of truth in code:** `ai-platform/src/prompt/composer.ts` (prior-turn rendering + second
output-shape offer); `ai-platform/src/validate/phases.ts` and `ai-platform/src/validate/index.ts`
(dual acceptance); H1 `ai-platform/src/context/context-request.ts` (`validateContextRequest`).

**Traces to:** spec **Freezes** (composer rendering of the supplied transcript; context-request
schema as a second permitted output shape alongside prose); FR-014–FR-018.

**Extends (does not rewrite):**
- D1 composer output contract
  (`specs/028-prompt-registry-composer/contracts/composer-output.md`) — `single_shot` part order,
  delimited context rendering, and registry pins remain intact.
- D6 response-validator contract
  (`specs/033-response-validator/contracts/response-validator.md`) — phase order, bounded repair,
  and structured-mode emission remain intact; conversational legs gain dual acceptance only.
- H1 context-request schema
  (`specs/044-conversational-manifest-schema/contracts/context-request-schema.md`) — one
  platform-owned `{key, arguments}` list; not a per-capability schema.

---

## 1. Overview

For a conversational capability, the composer renders the validated transcript as prior turns of
delimited typed data on the same footing as ordinary context, and offers the shared context-request
schema as a second permitted output shape alongside prose. The response validator accepts either a
valid prose answer or a valid context request; output that is neither fails under D6's existing
`validation_failed` path.

---

## 2. Prior-turn role tags (closed set)

The composer emits transcript parts using the closed canonical role-tag set (§5.3 / §4.3.6). It
MUST invent no tag of its own (FR-016):

| Transcript `kind` | Role tag | Payload rendering |
| --- | --- | --- |
| `user` | `user` | Turn `text` wrapped as `<turn kind="user">…</turn>` with `</` neutralization (R-10). Role tag remains `user` per §4.3.6 / §5.3; delimiting is a property of the payload shape. |
| `model` | `assistant` | Turn `text` wrapped as `<turn kind="model">…</turn>` with the same neutralization. |
| `context_requested` | `assistant` | Structured `requests` payload as neutralized JSON (`</` → `\u003c/`). |
| `context_resolved` | `data` | Turn `context` object rendered as delimited typed data, same footing as ordinary filtered context. |
| Ordinary filtered context | `data` | Unchanged D1 delimited typed rendering. |

`context_requested` turns are prior model terminals that asked for data. When rendered as prior
turns they use the closed `assistant` role (prior model turn) carrying the structured `requests`
payload — no invented tag. Budget counting of those turns remains a validator duty
(`transcript-validation-budgets.md`).

---

## 3. R-10 — no instruction leakage

- Transcript user turns and any context resolved during the conversation MUST be rendered as
  delimited, typed data on the same footing as ordinary context (FR-015).
- The composer MUST draw **no distinction** between free text from a clinical note and free text
  typed into a chat box.
- Escaping / block opacity (D1's delimited renderer and the conversational `<turn>` wrapper) stops
  embedded instruction-like text from acting as an instruction; this is a property of shape, not of
  prompt wording (R-10).
- Delimiter-like text inside `context_resolved` / filtered-context values MUST be neutralized
  (`</` → `\u003c/`) so a value cannot close its own block or open another.

---

## 4. Dual permitted output shapes

For conversational legs, two terminal output shapes are permitted:

| Shape | Validation | Meaning |
| --- | --- | --- |
| Prose answer | Same prose path D6 already accepts | Assistant answered; journal/`completed` as for any prose capability. |
| Context request | Platform-owned `{key, arguments}` list via H1 `validateContextRequest`, with each `key` drawn from the manifest's `permittedKeySet` | Assistant asked for clinic data; terminal event kind `context_requested` (H1); not a taxonomy code. |

| Rule | Detail |
| --- | --- |
| Offer | The composer offers the shared context-request schema as a second permitted output shape alongside prose (FR-014). |
| Accept either | The response validator MUST accept either shape (FR-017). |
| Reject neither | Output that is neither valid prose nor a valid context request MUST fail (FR-017) under D6's `validation_failed` path — H2 invents no new taxonomy code. Empty-array `[]` is not a valid context request for dual acceptance. |
| Platform-owned | The context-request schema remains the one H1 froze — not a per-capability schema (FR-018). |
| Structured-output config | Conversational dual offer is realized as prose in the derived format instruction and as dual acceptance in the response validator. `formatDirective` remains `{ mode: "prose", outputSchemaRef: null }` because provider structured-output / JSON-mode configuration cannot express a choice of two shapes; §4.3.6's "single source of truth for … the provider's structured-output/JSON-mode configuration" applies to structured-mode capabilities, not to this dual-shape prose offer. |

Phase order, bounded repair, and structured / `structured_atomic` emission are **not** redefined.
"Neither" rejections on the conversational dual-acceptance path are labeled `transport_parse`.

Conversational composition does **not** resolve `contextRenderingTemplateRef` — rendering uses
`permittedKeySet` delimited blocks. A missing or mis-pinned template MUST NOT fail a conversational
leg.

---

## 5. `single_shot` unaffected

A `single_shot` capability MUST NOT acquire transcript prior-turn rendering, budget codes, or the
second output shape from this slice's existence (delivery plan §3.8; FR-019). D1's frozen five-part
`single_shot` composition remains the path for those capabilities.

---

## 6. Out of scope of this contract

- Transcript wire shape and budget codes — see `transcript-wire.md` /
  `transcript-validation-budgets.md`.
- Emitting the `context_requested` SSE terminal and `AwaitingContext` journaling — H1 (terminal
  kind) and H3 (journal columns / client loop).
- Conversation evals — H4.
