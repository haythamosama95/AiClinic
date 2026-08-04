# Frozen Contract: Composer output (slice D1)

> **Status:** Frozen by slice D1 (`specs/028-prompt-registry-composer/spec.md` → Freezes → composer output contract).
> Later slices (D2/D3 invocation, D6 validator) **consume** this shape; they may extend it and may
> not rewrite it (delivery plan §2.3). Bind to this file, not to prose in `spec.md` or `plan.md`.
>
> Authority: `docs/architecture/17-ai-platform.md` §4.3.6, §5.3, §5.7, §9.5; `spec.md` Freezes → composer output contract.

**Review extension (D1-R):** H2 merged conversational transcript rendering into `composer.ts`
(architecture §4.3.6 conversational paragraph / §6.7): optional `transcript` input, `assistant`
parts for prior model / `context_requested` turns, and a conversational format instruction that
offers `CONTEXT_REQUEST_SCHEMA_ID` as a second permitted output shape alongside prose — same
documentation pattern as C1/C2/C3 review resolutions. Architecture §5.1 declares no
stop-sequences / tone / refusalPolicy fields; stopConditions forward A4 absence as `[]`; tone and
refusal live in reviewed system + business-rule artifacts until §5.1/§5.3 gain fields.

## 1. Scope

The composer (pipeline stage 10, §6.1) assembles the **canonical request** — the provider-neutral
representation frozen by A3 (`ai-platform/src/contracts/canonical.ts` → `CanonicalRequest`) — from
the resolved capability manifest, the resolved prompt artifacts, the filtered context payload, the
user intent, and the output constraints. This file freezes **what the composer produces and how the
parts are ordered/typed**, so that D2/D3 (routing/invocation) and D6 (validator) bind to a frozen
artifact rather than to spec prose.

The composer does **not** redefine the `CanonicalRequest` type (A3 owns it) and does **not** invent
role tags (§5.3 owns the closed set `system` / `user` / `assistant` / `data`). D1's original freeze
covers `single_shot` composition; H2's conversational extensions are recorded in §2 and §4.4 so
consumers switch on the full module behaviour.

## 2. Inputs

The composer is a pure function of:

| Input | Source (Consumes) | Type |
| --- | --- | --- |
| `manifest` | C1 resolved, frozen manifest (`ai-platform/src/capability/index.ts` `resolve` → `Manifest`) | `Manifest` (A4) |
| `filteredContext` | C2 `validateContext` ok branch (`ai-platform/src/context/validator.ts`) | `Record<string, unknown>` — only manifest-declared keys, each conforming to its published shape |
| `userIntent` | Caller intent, already shape-validated by the protocol adapter (A6) | `string` |
| `principal` | B3 immutable request principal (`ai-platform/src/identity/index.ts` → `Principal`) | `Principal` — read for correlation ids only; not re-verified |
| `requestReference` | Stage-9 journal row (required) | `string` — must match the journaled reference; the composer does not mint one |
| `transcript` | Optional. C2 validated transcript for `interactionMode: "conversational"` (H2) | `Transcript` — omitted for `single_shot` |

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

### 4.1 Ordered message parts (`single_shot`)

| Order | Role tag | Payload | Source |
| --- | --- | --- | --- |
| 1 | `system` | System instruction artifact content (verbatim) | `systemInstructionArtifactRef` resolved by registry |
| 2 | `system` | Each business-rule fragment content (verbatim), in `businessRuleFragmentRefs` order, as its own `system` part | `businessRuleFragmentRefs` resolved by registry |
| 3 | `system` | Derived output-format instruction (see §5) | derived from Output field group |
| 4 | `data` | Filtered context payload rendered through `contextRenderingTemplateRef` (see §6) | template substitution of `filteredContext` |
| 5 | `user` | User intent (verbatim) | `userIntent` |

A `data` part is data, never command (R-10): no provider mapping may promote it to an instruction
role. Adapters (D2/D5) bind to the role tag only and forward the payload unread (§4.3.6).

### 4.2 Scalar canonical-request fields

The composer populates these `CanonicalRequest` fields (A3 owns the field names):

- **output format directive** — derived per §5
- **max output tokens** — from `manifest.Economics.maxOutputTokens`
- **stop conditions** — forwarded via `stopConditionsFromManifest(manifest)`. A4 §5.1 declares no
  stop-sequences field on Output/Input, so the forwarded value is the empty list (`[]`) — absence,
  not an invented threshold. When §5.1 gains a stop-sequences field, this helper is the sole
  forwarding site.
- **sampling constraints** — `allowedLanguages` from `manifest.Input.allowedLanguages`
- **stream flag** — from the request (forwarded; the composer does not decide it)
- **deadline** — from the request (forwarded)
- **correlation ids** — `request_reference` from required input `requestReference`; `trace_id`
  from `principal.jti`
- **tool/function declarations** — reserved for future; D1 emits none

### 4.3 Output constraints carried on the canonical request

Per FR-004 (architecture §4.3.6 / §5.3), the canonical request carries the output constraints:
**max tokens, stop sequences, language, tone, refusal policy**. Operationalization under the
current A4/A3 schemas:

| Constraint | How D1 carries it |
| --- | --- |
| Max tokens | `maxOutputTokens` ← `Economics.maxOutputTokens` |
| Stop sequences | `stopConditions` ← `stopConditionsFromManifest` (empty list = A4 absence) |
| Language | `samplingConstraints.allowedLanguages` ← `Input.allowedLanguages` |
| Tone | Carried by the reviewed **system instruction** artifact (advisory / professional prose). A4 §5.1 and A3 §5.3 declare no `tone` field on the fixture manifest or `CanonicalRequest`. |
| Refusal policy | Carried by reviewed **business-rule fragment** artifacts. A4 §5.1 and A3 §5.3 declare no `refusalPolicy` field on the fixture manifest or `CanonicalRequest`. |

The composer invents no threshold, limit, or default beyond forwarding manifest values and
artifact content (spec Out of Scope). The fixture manifest does **not** declare tone or refusal
fields — those live in prompt artifacts until §5.1/§5.3 gain them.

### 4.4 Conversational composition (H2 merge)

When `manifest.interactionMode === "conversational"` and `transcript` is supplied:

| Extension | Behaviour |
| --- | --- |
| Format instruction | Offers prose **or** a JSON array conforming to `CONTEXT_REQUEST_SCHEMA_ID` using keys from `permittedKeySet` |
| Prior turns | Spliced after the three `system` parts and before the filtered-context `data` part |
| `user` turns | `role: "user"`, text verbatim |
| `model` turns | `role: "assistant"`, text verbatim |
| `context_requested` turns | `role: "assistant"`, `JSON.stringify(requests)` |
| `context_resolved` turns | `role: "data"`, delimited typed blocks; keys sorted for stable order; `shape` equals the key id (platform convention: published shape ref === key id) |
| Filtered context `data` part | Keys iterated in **`permittedKeySet` order** (not `Object.entries` order); `shape` equals the key id |

`single_shot` composition (§4.1) is unchanged by this extension.

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

Every context part is a single `data` part whose payload is produced by rendering
`filteredContext` **through** the capability's `contextRenderingTemplateRef` artifact
(`renderThroughTemplate`). The fixture template uses one block per key:

```
<key name="visit.chief_complaint@v1" shape="visit.chief_complaint@v1">
{{visit.chief_complaint@v1}}
</key>
```

Rules frozen by this contract:

- For `single_shot`, iterate `Context requirements` in order. For each key: if absent from
  `filteredContext`, strip that key's `<key …>…</key>` block from the template; if present,
  substitute `{{key}}` with `JSON.stringify(value)` after neutralizing literal `</` to `\u003c/`.
- If any `{{…}}` placeholders remain after processing, composition fails with `internal_error`.
- Changing the template artifact MUST change the data-part output (the pin guards live content).
- The value is emitted as substituted JSON — no preamble, no instruction (§4.3.6).
- Neutralization of `</` stops a value from closing its own block or opening another
  (Clarification Q3 / R-10). T9 asserts an instruction embedded in a context value does not appear
  in any `system`/`user` instruction part and remains inside its `data` block with `role: "data"`.
- The payload of a `data` part is **opaque to adapters** (§4.3.6): adapters bind to the role tag
  only and forward the payload unread.

Conversational filtered-context rendering follows §4.4 (permittedKeySet order); the template
existence check still applies.

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
cannot be parsed, a template that cannot render the filtered context, a missing required
`requestReference`) rejects the request with `internal_error` and invokes no provider. Unexpected
throws are logged with `console.error` including the trace id (`principal.jti`) before returning
`internal_error`. Build-time pin failures (missing/altered pinned artifact) are build failures, not
runtime taxonomy codes — they fail the build before any request runs (spec Edge Cases → Error codes
this slice can emit). T12 asserts the failure path.

## 9. Invariants this contract freezes for consumers

- **No provider-shaped field** in the composed canonical request (§5.3, FR-007). T11 binds to
  A3's `assertNoProviderShapedFieldNames` over nested keys. D2/D3/D6 may rely on this.
- **`data` is data, never command** (R-10). D2/D5 adapters must not promote a `data` part to an
  instruction role; D6's injection-echo guard binds to this.
- **Output schema is the single source of truth** for the format instruction (D1), the provider's
  structured-output configuration (D2/D5), and the response validator (D6). D6 extends this by
  reading the same `outputSchemaRef`; it must not receive a separately authored format instruction.
- **One resolved prompt version per request** (FR-008). C3 records it; F1 evals treat a prompt
  change as a new capability build (§5.7).
- **Template governs rendering** (FR-004 / FR-006). The data part is produced by substituting the
  pinned template; the hash pin guards live content.
