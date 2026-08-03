# Canonical inference wire shapes (A3)

Frozen §5.3 wire shapes for the four canonical inference elements. Field names are
the **Field** identifiers from amended architecture §5.3 (not contents prose); later
slices (D2 composer, D3 provider port, D6 stream broker, D9 validator) **consume**
this artifact — they extend, never rewrite these names or kinds.

**Source of truth in code:** `ai-platform/src/contracts/canonical.ts` (`CANONICAL_FIELD_MANIFEST`,
typed element interfaces — not `unknown` — and the owned JSON codec).

**Traces to:** spec **Freezes** entry; FR-001–FR-009.

---

## 1. Overview

A3 defines four provider-neutral elements that sit between the composer and the
provider adapters. Each element is a JSON object whose keys are exactly the manifest
fields listed below — no provider-shaped aliases (`messages`, `completion`, `n`,
`frequency_penalty`, `top_p`, `logprobs`, …) and no extra keys on the wire.

The owned codec (`encodeCanonical*` / `decodeCanonical*`) emits only manifest-declared
keys and **rejects** (fail closed) any provider-shaped or unknown key present on encode
input or decode wire — it does not silently strip extras.

---

## 2. Canonical request

**Type:** `CanonicalRequest`

| Field | Contents |
| --- | --- |
| `parts` | Ordered array of role-tagged parts (e.g. `{ role, content }`). |
| `formatDirective` | Output-format specification (e.g. free text or JSON with schema). |
| `samplingConstraints` | Sampling parameters (e.g. temperature, top-k). |
| `maxOutputTokens` | Maximum output token budget (number). |
| `stopConditions` | Stop sequences (string array). |
| `toolDeclarations` | Placeholder array; no behaviour wired in A3 (reserved for future). |
| `stream` | Whether the inference is streamed (boolean). |
| `deadline` | Request deadline in milliseconds (number \| null). |
| `correlationIds` | Request reference and trace id (e.g. `request_reference`, `trace_id`). |

**Codec:** `encodeCanonicalRequest` / `decodeCanonicalRequest`

---

## 3. Canonical stream chunk

**Type:** `CanonicalStreamChunk`

| Field | Contents |
| --- | --- |
| `sequenceNumber` | Monotonic position within the stream (number). |
| `kind` | One of the four closed chunk kinds (see §3.1). |
| `payload` | Kind-specific payload (opaque object). |
| `terminal` | Whether this chunk ends the sequence (boolean). |

**Codec:** `encodeCanonicalChunk` / `decodeCanonicalChunk`

### 3.1 Closed chunk-kind set

The `kind` field MUST be exactly one of:

| Kind | Role |
| --- | --- |
| `text_delta` | Incremental text output. |
| `partial_structured` | Incremental structured output. |
| `usage` | Token or resource usage update. |
| `provider_note` | Provider diagnostic note. |

No other kind is accepted. `CANONICAL_CHUNK_KINDS` in code is the exhaustive set;
`isCanonicalChunkKind` rejects any other string on decode.

### 3.2 Terminal-flag invariant

Across any non-empty chunk sequence, exactly one chunk MUST carry `terminal: true`
— never zero, never more than one (§5.5 rule 4). `assertExactlyOneTerminal` enforces
this invariant; an empty sequence is rejected.

---

## 4. Canonical result

**Type:** `CanonicalResult`

| Field | Contents |
| --- | --- |
| `finalContent` | Completed output (object; shape depends on output format). |
| `usage` | Input, output, and cached token counts (e.g. `input`, `output`, `cached`). |
| `providerModel` | Provider and model identifiers used for the attempt. |
| `finishReason` | Why generation stopped (string). |
| `providerRequestId` | Provider-assigned request identifier (string). |
| `timing` | Timing metrics (e.g. `queue_ms`, `provider_ms`, `total_ms`). |

**Codec:** `encodeCanonicalResult` / `decodeCanonicalResult`

---

## 5. Canonical error

**Type:** `CanonicalError`

| Field | Contents |
| --- | --- |
| `taxonomyCode` | A2 `TaxonomyCode` — the closed eighteen-code set from `ai-platform/src/errors.ts`. Unrecognised values are rejected on decode. |
| `retryability` | Whether the caller may retry (boolean). |
| `providerNative` | Provider diagnostics only (e.g. `{ code, message }`). |
| `consumedBudget` | Whether quota was consumed (boolean). |

**Codec:** `encodeCanonicalError` / `decodeCanonicalError`

---

## 6. Provider-shape guard

`assertNoProviderShapedFieldNames` rejects any manifest key equal to a known
provider-shaped token. The contract test T-A3-05 asserts the manifest is clean,
that introducing a provider-shaped key makes the guard fail, and that the codec
rejects a provider-shaped extra key on encode/decode rather than stripping it.
T-A3-08 asserts decode rejects unknown non-provider extra keys on every element.
T-A3-09 asserts decoded elements expose typed field shapes and the closed
`CANONICAL_MESSAGE_ROLES` set (`system`, `user`, `assistant`, `data`).
T-A3-10 asserts the manifest uses amended §5.3 camelCase identifiers and contains
no contents-prose keys.

**Frozen rejection set (A3):** `messages`, `completion`, `n`, `frequency_penalty`,
`top_p`, `logprobs`.
