# Canonical inference wire shapes (A3)

Frozen §5.3 wire shapes for the four canonical inference elements. Field names are
verbatim from the architecture table; later slices (D2 composer, D3 provider port, D6
stream broker, D9 validator) **consume** this artifact — they extend, never rewrite
these names or kinds.

**Source of truth in code:** `ai-platform/src/contracts/canonical.ts` (`CANONICAL_FIELD_MANIFEST`,
derived types, and the owned JSON codec).

**Traces to:** spec **Freezes** entry; FR-001–FR-009.

---

## 1. Overview

A3 defines four provider-neutral elements that sit between the composer and the
provider adapters. Each element is a JSON object whose keys are exactly the manifest
fields listed below — no provider-shaped aliases (`messages`, `completion`, `n`,
`frequency_penalty`, `top_p`, `logprobs`, …) and no extra keys on the wire.

The owned codec (`encodeCanonical*` / `decodeCanonical*`) emits only manifest-declared
keys and drops any others present in the input object.

---

## 2. Canonical request

**Type:** `CanonicalRequest`

| Field name | Contents |
| --- | --- |
| `ordered role-tagged message parts` | Ordered array of role-tagged parts (e.g. `{ role, content }`). |
| `output format directive` | Output-format specification (e.g. free text or JSON with schema). |
| `sampling constraints` | Sampling parameters (e.g. temperature, top-k). |
| `max output tokens` | Maximum output token budget (number). |
| `stop conditions` | Stop sequences (string array). |
| `tool/function declarations (reserved for future)` | Placeholder array; no behaviour wired in A3. |
| `stream flag` | Whether the inference is streamed (boolean). |
| `deadline` | Request deadline in milliseconds (number). |
| `correlation ids` | Request reference and trace id (e.g. `request_reference`, `trace_id`). |

**Codec:** `encodeCanonicalRequest` / `decodeCanonicalRequest`

---

## 3. Canonical stream chunk

**Type:** `CanonicalStreamChunk`

| Field name | Contents |
| --- | --- |
| `sequence number` | Monotonic position within the stream (number). |
| `kind` | One of the four closed chunk kinds (see §3.1). |
| `payload` | Kind-specific payload (opaque object). |
| `terminal flag` | Whether this chunk ends the sequence (boolean). |

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

Across any non-empty chunk sequence, exactly one chunk MUST carry `"terminal flag": true`
— never zero, never more than one (§5.5 rule 4). `assertExactlyOneTerminal` enforces
this invariant; an empty sequence is rejected.

---

## 4. Canonical result

**Type:** `CanonicalResult`

| Field name | Contents |
| --- | --- |
| `final content` | Completed output (object; shape depends on output format). |
| `usage counters` | Input, output, and cached token counts (e.g. `input`, `output`, `cached`). |
| `provider+model actually used` | Provider and model identifiers used for the attempt. |
| `finish reason` | Why generation stopped (string). |
| `provider request id` | Provider-assigned request identifier (string). |
| `timing breakdown` | Timing metrics (e.g. `queue_ms`, `provider_ms`, `total_ms`). |

**Codec:** `encodeCanonicalResult` / `decodeCanonicalResult`

---

## 5. Canonical error

**Type:** `CanonicalError`

| Field name | Contents |
| --- | --- |
| `taxonomy code` | A2 `TaxonomyCode` — the closed eighteen-code set from `ai-platform/src/errors.ts`. Unrecognised values are rejected on decode. |
| `retryability` | Whether the caller may retry (boolean). |
| `provider-native code and message` | Provider diagnostics only (e.g. `{ code, message }`). |
| `whether the attempt consumed budget` | Whether quota was consumed (boolean). |

**Codec:** `encodeCanonicalError` / `decodeCanonicalError`

---

## 6. Provider-shape guard

`assertNoProviderShapedFieldNames` rejects any manifest key equal to a known
provider-shaped token. The contract test T-A3-05 asserts the manifest is clean and
that introducing a provider-shaped key makes the guard fail.

**Frozen rejection set (A3):** `messages`, `completion`, `n`, `frequency_penalty`,
`top_p`, `logprobs`.
