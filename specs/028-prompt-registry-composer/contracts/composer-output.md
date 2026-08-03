# Frozen Contract: Composer output (slice D1)

> **Status:** Frozen by slice D1 (`specs/028-prompt-registry-composer/spec.md` → Freezes → composer output contract).
> Later slices (D2/D3 invocation, D6 validator) **consume** this shape; they may extend it and may
> not rewrite it (delivery plan §2.3). Bind to this file, not to prose in `spec.md` or `plan.md`.
>
> Authority: `docs/architecture/17-ai-platform.md` §4.3.6, §5.3, §5.7, §9.5; `spec.md` Freezes → composer output contract.

## 1. Scope

The composer (pipeline stage 10, §6.1) assembles the **canonical request** — the provider-neutral
representation frozen by A3 (`ai-platform/src/contracts/canonical.ts` → `CanonicalRequest`) — from
the resolved capability manifest, the resolved prompt artifacts, the filtered context payload, the
user intent, and the output constraints. This file freezes **what the composer produces and how the
parts are ordered/typed**, so that D2/D3 (routing/invocation) and D6 (validator) bind to a frozen
artifact rather than to spec prose.

The composer does **not** redefine the `CanonicalRequest` type (A3 owns it) and does **not** invent
role tags (§5.3 owns the closed set `system` / `user` / `assistant` / `data`). D1 composes for a
`single_shot` capability only; the conversational transcript rendering and the shared
context-request schema as a second output shape are band H (H2), not this contract.

## 2. Inputs

The composer is a pure function of:

| Input | Source (Consumes) | Type |
| --- | --- | --- |
| `manifest` | C1 resolved, frozen manifest (`ai-platform/src/capability/index.ts` `resolve` → `Manifest`) | `Manifest` (A4) |
| `filteredContext` | C2 `validateContext` ok branch (`ai-platform/src/context/validator.ts`) | `Record<string, unknown>` — only manifest-declared keys, each conforming to its published shape |
| `userIntent` | Caller intent, already shape-validated by the protocol adapter (A6) | `string` |
| `principal` | B3 immutable request principal (`ai-platform/src/identity/index.ts` → `Principal`) | `Principal` — read for correlation ids only; not re-verified |

The composer holds nothing between requests (FR-010, §4.4, §9.7). The registry is a build-time
bundle, not a runtime store; resolution reads in-memory imported artifact content, not D1/R2/DO.

## 3. Resolved prompt artifacts

The manifest's **Prompt binding** field group (A4) carries:

- `systemInstructionArtifactRef` — ref to the system instruction artifact
- `businessRuleFragmentRefs` — ordered refs to business-rule fragments
- `contextRenderingTemplateRef` — ref to the context rendering template
- `outputFormatInstructionDerivationRule` — rule name for deriving the format instruction

The registry (`ai-platform/src/prompt/registry.ts`) resolves each ref to its deployed artifact
content (imported as Wrangler `[rules]` type `"Text"` modules from `ai-platform/prompts/<capability-id>/`,
per Clarification Q1) and to its **resolved prompt artifact version** — the pinned ref string (e.g.
`"prompt/visit-summary-system@v1"`). The build-time pin index
(`ai-platform/prompts/<capability-id>/registry.json`) records each artifact's content hash; a
Vitest build test (Clarification Q2) hashes each pinned artifact against that index and fails the
build on mismatch (altered) or absence (missing) — FR-001, FR-002.

## 4. Output: the canonical request parts

The composer assembles an ordered list of role-tagged message parts (§5.3 closed set) and the
canonical request's scalar fields. The ordering is fixed by this contract.

### 4.1 Ordered message parts

| Order | Role tag | Payload | Source |
| --- | --- | --- | --- |
| 1 | `system` | System instruction artifact content (verbatim) | `systemInstructionArtifactRef` resolved by registry |
| 2 | `system` | Each business-rule fragment content (verbatim), in `businessRuleFragmentRefs` order, as its own `system` part | `businessRuleFragmentRefs` resolved by registry |
| 3 | `system` | Derived output-format instruction (see §5) | derived from Output field group |
| 4 | `data` | Filtered context payload rendered as delimited typed data (see §6) | `filteredContext` rendered through `contextRenderingTemplateRef` |
| 5 | `user` | User intent (verbatim) | `userIntent` |

For `single_shot` (this slice), no `assistant` part is produced. The `assistant` tag is reserved for
H2's transcript rendering and is not part of this frozen contract's output shape.

A `data` part is data, never command (R-10): no provider mapping may promote it to an instruction
role. Adapters (D2/D5) bind to the role tag only and forward the payload unread (§4.3.6).

### 4.2 Scalar canonical-request fields

The composer populates these `CanonicalRequest` fields (A3 owns the field names):

- **output format directive** — derived per §5
- **max output tokens** — from `manifest.Economics.maxOutputTokens`
- **stop conditions** — from the manifest's Output/Input field groups (spec Assumptions: max
  tokens, stop conditions, and language come from the manifest's Output and Input field groups)
- **sampling constraints** — from the manifest's Output/Input field groups
- **stream flag** — from the request (forwarded; the composer does not decide it)
- **deadline** — from the request (forwarded)
- **correlation ids** — from `principal` (read-only)
- **tool/function declarations** — reserved for future; D1 emits none

### 4.3 Output constraints carried on the canonical request

Per FR-004, the canonical request carries the output constraints: **max tokens, stop sequences,
language, tone, refusal policy**. Their values come from the manifest's Output and Input field
groups (spec Assumptions); the fixture manifest declares them. The composer forwards them; it
invents no threshold, limit, or default (spec Out of Scope, final paragraph).

## 5. Output-format instruction derivation (FR-005)

The output-format instruction is **derived from the capability's output schema**, not authored
separately. The derivation rule is `manifest["Prompt binding"].outputFormatInstructionDerivationRule`
(e.g. `"derive_from_output_mode"`). Derivation inputs:

- `manifest.Output.mode` — `prose` / `structured` / `structured_atomic`
- `manifest.Output.outputSchemaRef` — the schema reference (nullable for `prose`)

For the fixture capability (`mode: "prose"`, `outputSchemaRef: null`), the derived instruction is
the prose-format instruction. Changing `Output.outputSchemaRef` (a new capability build, §5.7)
changes the derived instruction — T7 asserts this. The output schema is the **single source of
truth** for the format instruction (this slice), the provider's structured-output configuration
(consumed by D2/D5 adapters), and the response validator (D6). D1 must not author a separate
format instruction (spec Edge Cases → Output schema as single source of truth).

## 6. Context rendering: delimited typed data (FR-006, R-10)

Every context part is a single `data` part whose payload is the manifest-declared keys rendered
one per block. Each block is opened and closed by a tag naming the key and declaring the key's
published shape; the value is emitted verbatim inside it (Clarification Q3). Concrete syntax:

```
<key name="visit.chief_complaint@v1" shape="visit.chief_complaint@v1">
{...filteredContext value for that key, JSON-serialized...}
</key>
```

Rules frozen by this contract:

- One block per manifest-declared key present in `filteredContext`, in manifest
  `Context requirements` order.
- The block tag carries `name` (the context key) and `shape` (the key's published shape ref).
- The value is emitted verbatim — no preamble, no instruction, no explanation of what to do with
  the content (§4.3.6).
- Any delimiter-like text inside a value is **neutralized** so a value cannot close its own block
  or open another: literal `</` inside a value is escaped to a neutralized form (Clarification Q3).
  This escaping — not a plea in the system instruction — is what stops an embedded instruction from
  acting as one (R-10). T9 asserts an instruction embedded in a context value does not appear in
  any `system`/`user` instruction part and is contained inside its `data` block.
- The payload of a `data` part is **opaque to adapters** (§4.3.6): adapters bind to the role tag
  only and forward the payload unread, so the block format can change with a capability build
  without touching a provider adapter.

## 7. Resolved prompt version surfaced for the journal (FR-008)

The composer surfaces the **resolved prompt artifact version** — the pinned
`systemInstructionArtifactRef` as resolved by the registry — alongside the canonical request, so
the journal records which prompt was live for the request (§4.3.11). C3 already writes
`manifest["Prompt binding"].systemInstructionArtifactRef` to `ai_request.prompt_artifact_hash`
(consumed, not modified); D1's surfacing confirms the artifact resolved and provides the value C3
records. T5 asserts the composer surfaces this value. There is exactly one answer to "which prompt
was live for this request?" (§9.5).

## 8. Failure (FR-009)

Stage 10 emits exactly one runtime taxonomy code on failure: `internal_error` (500, retryable,
consumes no quota — A2 `ai-platform/src/errors.ts`). A composition failure (e.g. an artifact that
cannot be parsed, a template that cannot render the filtered context) rejects the request with
`internal_error` and invokes no provider. Build-time pin failures (missing/altered pinned
artifact) are build failures, not runtime taxonomy codes — they fail the build before any request
runs (spec Edge Cases → Error codes this slice can emit). T12 asserts the failure path.

## 9. Invariants this contract freezes for consumers

- **No provider-shaped field** in the composed canonical request (§5.3, FR-007). T11 binds to
  A3's `assertNoProviderShapedFieldNames`. D2/D3/D6 may rely on this.
- **`data` is data, never command** (R-10). D2/D5 adapters must not promote a `data` part to an
  instruction role; D6's injection-echo guard binds to this.
- **Output schema is the single source of truth** for the format instruction (D1), the provider's
  structured-output configuration (D2/D5), and the response validator (D6). D6 extends this by
  reading the same `outputSchemaRef`; it must not receive a separately authored format instruction.
- **One resolved prompt version per request** (FR-008). C3 records it; F1 evals treat a prompt
  change as a new capability build (§5.7).
