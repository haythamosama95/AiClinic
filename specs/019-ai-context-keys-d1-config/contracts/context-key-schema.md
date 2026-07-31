# Context key vocabulary and published shapes (A5)

Frozen §5.2 context-key naming, storage-named rejection, published-shape contract, first
key shape, and backward-compatible evolution rules. Later slices **consume** this artifact —
they extend, never rewrite these rules:

| Slice | Role |
| --- | --- |
| **C2** (context validator) | Enforces required keys, declared shapes, size bounds, and branch consistency; rejects shape violations as `context_invalid`; drops undeclared keys. |
| **C3** (journal writer) | Journals the context payloads supplied on each request; does not redefine key names or shapes. |
| **E3** (Context Resolver) | Resolves each manifest-declared key to a payload conforming to the published shape under caller RLS; contract test asserts every active manifest key is resolvable. |

**Source of truth in code:** `ai-platform/src/context/index.ts` (`KeyShape`, `KeyShapeField`,
`VISIT_CHIEF_COMPLAINT_V1`, `VISIT_CHIEF_COMPLAINT_V1_SHAPE`, `validateKey`, `validatePayload`).

**Traces to:** spec **Freezes** entry; FR-001–FR-007.

---

## 1. Overview

A **context key** is a stable, versioned name for a unit of business data in domain vocabulary.
Context flows **client → platform** only. The platform never learns table names, column names, SQL,
or RPC names.

Each key has a **platform-published shape** — field names, types, cardinality, and units — which
is the *only* schema knowledge shared between the client Context Resolver and the platform
validator. Manifest **Context requirements** (A4) reference keys by name; A5 publishes the key
vocabulary and the first key's shape that those references resolve to.

---

## 2. Naming contract

### 2.1 Key format

A context key MUST follow `domain.concept@vN`:

| Segment | Rule |
| --- | --- |
| `domain` | Lowercase letter followed by lowercase letters, digits, or underscores (`[a-z][a-z0-9_]*`). |
| `concept` | One or more dot-separated segments, each matching the domain segment rule. At least one dot MUST separate domain from concept (e.g. `visit.vitals`, not `visit_vitals`). |
| `@vN` | Literal `@v` followed by a positive integer with no leading zero (`v1`, `v2`, … `v10`). |

**Normative pattern (implementation):**

```text
^([a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+)@v([1-9]\d*)$
```

Keys that fail this pattern are rejected with code `malformed_key`.

### 2.2 Meaning, not storage

> A context key names **what the data means to a clinician**, never where it is stored.

`visit.vitals@v1` is correct. Keys that mirror storage artefacts are not context keys even when
the underlying table or RPC exists.

### 2.3 §5.2 example vocabulary

The following keys are accepted by `validateKey` as well-formed, domain-meaningful names at
version 1. Only keys with a published shape (§5) may pass `validatePayload`.

| Key | Shape published in A5 |
| --- | --- |
| `patient.demographics@v1` | No (vocabulary only) |
| `visit.vitals@v1` | No (vocabulary only) |
| `visit.chief_complaint@v1` | **Yes** (first key — §4) |
| `medication.active_list@v1` | No (vocabulary only) |
| `lab.recent_results@v1` | No (vocabulary only) |
| `clinic.branch_profile@v1` | No (vocabulary only) |

### 2.4 Unknown version rejection

A key that matches the format and vocabulary domain but whose `@vN` suffix is not in the
published vocabulary MUST be rejected with code `unknown_version`.

**Example:** `visit.vitals@v9` is rejected because `v9` is not published.

---

## 3. Storage-named key rejection

Keys whose concept segment names storage rather than clinical meaning MUST be rejected with code
`storage_named_key`, regardless of whether the referenced artefact exists.

### 3.1 Rejection rules

| Pattern | Example (rejected) | Rationale |
| --- | --- | --- |
| Concept ends with `_table` | `visits_vitals_table@v1` | Names a database table, not clinical meaning. |
| Concept matches `get_*_rpc` | `get_visit_vitals_rpc@v1` | Names an RPC, not clinical meaning. |

The rule is about **meaning**, not existence. A storage-named string that happens to be valid
`domain.concept@vN` syntax is still rejected.

### 3.2 Malformed format examples

These are rejected with `malformed_key` (not `storage_named_key`):

| Key | Violation |
| --- | --- |
| `visit.vitals` | Missing `@vN` suffix. |
| `visit_vitals@v1` | Underscore instead of dot between domain and concept. |
| `visit@v1` | No concept segment after domain. |
| `visit..vitals@v1` | Empty segment (double dot). |
| `visit.vitals@1` | Version missing `v` prefix. |
| `visit.vitals@version1` | Non-numeric version. |

---

## 4. Published shape contract

### 4.1 KeyShape

Each published key is described by a `KeyShape` object:

| Member | Type | Contents |
| --- | --- | --- |
| `key` | `string` | The context key in `domain.concept@vN` form. |
| `fields` | `KeyShapeField[]` | Ordered list of field declarations. |

### 4.2 KeyShapeField

Each field declares four properties — the only schema dimensions shared between client and
platform:

| Property | Type | Contents |
| --- | --- | --- |
| `name` | `string` | Wire field name (snake_case in A5). |
| `type` | `FieldType` | One of `string`, `number`, `boolean`. |
| `cardinality` | `FieldCardinality` | Presence and length constraint (§4.3). |
| `units` | `string \| null` | Semantic unit constraint on the value, or `null` when none applies. |

### 4.3 FieldCardinality

| Value | Meaning |
| --- | --- |
| `"required"` | Field MUST be present with a non-`undefined` value. |
| `"optional"` | Field MAY be absent or `undefined`. |
| `{ maxLength: N }` | String field that, when present, MUST NOT exceed `N` characters. Does not imply required presence — only `"required"` does. |

### 4.4 Units

When `units` is non-null, the string value MUST conform to the declared unit:

| Unit | Constraint |
| --- | --- |
| `uuid` | RFC 4122 UUID string (lowercase hex with hyphens). |
| `iso8601` | UTC timestamp `YYYY-MM-DDTHH:MM:SS[.sss]Z` (milliseconds optional, trailing `Z` required). |
| `null` | No unit constraint beyond `type` and `cardinality`. |

Unknown unit strings are accepted at the type level but impose no additional check in A5.

### 4.5 Payload wire encoding

A conforming payload is a **JSON object** (not `null`, not an array) whose keys are a subset of the
published field names. Extra keys are not validated by A5's `validatePayload` (C2 drops undeclared
keys before forwarding).

### 4.6 Validation outcomes

`validatePayload(key, payload)` returns `{ ok: true }` or `{ ok: false, code, field? }`.

| Code | Condition |
| --- | --- |
| `malformed_key` | Key fails §2.1 format. |
| `storage_named_key` | Key fails §3.1 storage-named rule. |
| `unknown_version` | Key not in published vocabulary (§2.4). |
| `unknown_shape` | Key accepted but no `KeyShape` registered (should not occur for vocabulary keys once shapes are added). |
| `type` | Value is not the declared `FieldType`, or payload is not a plain object. |
| `cardinality` | String exceeds `maxLength`. |
| `units` | String fails the declared unit constraint. |
| `missing_field` | Required field absent; `field` names the missing field. |

---

## 5. First published key shape

Per Open Decision 1 (visit-summary capability), A5 publishes the shape for
`visit.chief_complaint@v1` — the context the first capability requires.

**Constant:** `VISIT_CHIEF_COMPLAINT_V1` = `"visit.chief_complaint@v1"`

**Shape:** `VISIT_CHIEF_COMPLAINT_V1_SHAPE`

| Field | Type | Cardinality | Units |
| --- | --- | --- | --- |
| `visit_id` | `string` | `required` | `uuid` |
| `complaint` | `string` | `{ maxLength: 10000 }` | `null` |
| `recorded_at` | `string` | `optional` | `iso8601` |

### 5.1 Conforming payload example

```json
{
  "visit_id": "550e8400-e29b-41d4-a716-446655440000",
  "complaint": "Persistent headache for three days.",
  "recorded_at": "2026-07-31T12:00:00.000Z"
}
```

`recorded_at` and `complaint` may be omitted. Only `visit_id` is required on submit; when
`complaint` is present its length MUST NOT exceed 10 000 characters.

### 5.2 E3 binding

The first context RPC (E3) MUST return a payload that passes `validatePayload("visit.chief_complaint@v1", …)`
under the caller's RLS. The Flutter contract test suite asserts every declared key of every active
manifest is resolvable to its published shape.

### 5.3 Full JSON representation

Machine-readable snapshot of the A5 context-key contract as implemented in
`ai-platform/src/context/index.ts`. Shapes, vocabulary, and validation codes below are normative
for binding tests and downstream slices (C2, C3, E3).

```json
{
  "contract": "context-key-schema",
  "slice": "A5",
  "naming": {
    "format": "domain.concept@vN",
    "pattern": "^([a-z][a-z0-9_]*(?:\\.[a-z][a-z0-9_]*)+)@v([1-9]\\d*)$"
  },
  "storage_named_rejection": {
    "rules": [
      { "pattern": "*_table", "example": "visits_vitals_table@v1", "code": "storage_named_key" },
      { "pattern": "get_*_rpc", "example": "get_visit_vitals_rpc@v1", "code": "storage_named_key" }
    ]
  },
  "vocabulary": [
    "patient.demographics@v1",
    "visit.vitals@v1",
    "visit.chief_complaint@v1",
    "medication.active_list@v1",
    "lab.recent_results@v1",
    "clinic.branch_profile@v1"
  ],
  "published_shapes": {
    "visit.chief_complaint@v1": {
      "key": "visit.chief_complaint@v1",
      "fields": [
        {
          "name": "visit_id",
          "type": "string",
          "cardinality": "required",
          "units": "uuid"
        },
        {
          "name": "complaint",
          "type": "string",
          "cardinality": { "maxLength": 10000 },
          "units": null
        },
        {
          "name": "recorded_at",
          "type": "string",
          "cardinality": "optional",
          "units": "iso8601"
        }
      ]
    }
  },
  "field_types": ["string", "number", "boolean"],
  "cardinality_forms": [
    "required",
    "optional",
    { "maxLength": "<positive integer>" }
  ],
  "units": {
    "uuid": "RFC 4122 UUID string (lowercase hex with hyphens)",
    "iso8601": "UTC timestamp YYYY-MM-DDTHH:MM:SS[.sss]Z",
    "null": "No unit constraint beyond type and cardinality"
  },
  "validation_result": {
    "success": { "ok": true },
    "failure": { "ok": false, "code": "<code>", "field": "<optional field name>" }
  },
  "validation_codes": [
    "malformed_key",
    "storage_named_key",
    "unknown_version",
    "unknown_shape",
    "type",
    "cardinality",
    "units",
    "missing_field"
  ],
  "conforming_payload_example": {
    "visit.chief_complaint@v1": {
      "visit_id": "550e8400-e29b-41d4-a716-446655440000",
      "complaint": "Persistent headache for three days.",
      "recorded_at": "2026-07-31T12:00:00.000Z"
    }
  }
}
```

Only `visit.chief_complaint@v1` has a `published_shapes` entry in A5; the other vocabulary keys
accept `validateKey` but return `unknown_shape` from `validatePayload` until a later slice
registers their shapes.

---

## 6. Backward-compatible evolution

Rules trace to §5.2 Evolution and FR-007. Overlap and deprecation **behaviour** is out of scope
(band J).

### 6.1 Adding an optional context key

Adding a new **optional** context key to a capability manifest is backward compatible. Existing
clients that do not supply the key continue to work; the validator (C2) treats absence as
acceptable when the manifest marks the key optional.

No new `@vN` suffix is required for the capability itself when only an optional key is added,
provided no existing key shape changes.

### 6.2 Adding a required context key

Adding a new **required** context key to a capability requires a **new capability version** (A4
manifest `version` bump). Clients on the old manifest version are not expected to supply the new
key until they refresh their manifest cache.

### 6.3 Changing a published shape

Any change to a key's published shape — adding a required field, changing a field type, tightening
cardinality, or changing units — requires:

1. A **new key version** (`@vN+1`, e.g. `visit.chief_complaint@v2`).
2. A **new capability version** that references the new key version in Context requirements.

The prior `@vN` shape remains frozen for manifests that still reference it. A5 does not define
overlap windows or deprecation messaging (band J).

### 6.4 Adding an optional field to an existing shape

Adding an optional field to an existing key's shape is a **shape change** under §6.3 and therefore
requires a new key version and a new capability version. Clients and the platform negotiate only
through versioned key names, not through in-place schema drift.

### 6.5 Vocabulary growth

New `domain.concept@v1` keys may be added to the vocabulary and given published shapes in a
later slice. Each addition is additive: existing keys and shapes are never rewritten in place.

---

## 7. Validator API surface

Exported from `ai-platform/src/context/index.ts`:

| Export | Role |
| --- | --- |
| `validateKey(key)` | Enforces §2–§3; returns `ValidationResult`. |
| `validatePayload(key, payload)` | Runs `validateKey` then checks payload against the published `KeyShape`. |
| `KeyShape`, `KeyShapeField`, `FieldType`, `FieldCardinality`, `ValidationResult` | Types for manifest binding, tests, and later slices. |
| `VISIT_CHIEF_COMPLAINT_V1`, `VISIT_CHIEF_COMPLAINT_V1_SHAPE` | First key constant and shape (§5). |

Contract tests `T-A5-01` through `T-A5-10` in `ai-platform/test/context.test.ts` pin this surface.

---

## 8. Consumer obligations

### 8.1 C2 — context validator

- Consult the manifest's Context requirements for the ordered key list and required/optional flags.
- Call `validatePayload` (or equivalent logic) for each supplied key against its published shape.
- Reject shape violations with taxonomy code `context_invalid`.
- Reject missing required keys with `context_required` and the missing-key manifest.
- Drop keys not declared in the manifest before forwarding to the composer.

### 8.2 C3 — journal writer

- Record the context payloads actually supplied on the request.
- Store keys by their `domain.concept@vN` string; do not transform field names.
- Rely on A5's D1 schema (`ai_request` and related entities); do not embed shape definitions in
  journal rows.

### 8.3 E3 — Context Resolver

- Maintain a generic key → resolver registry (no capability id on the API).
- Assemble payloads that conform to the `KeyShape` published here for each resolved key.
- Cache resolver results only within a screen scope.
- The first RPC MUST satisfy `visit.chief_complaint@v1` (§5).
