# Capability manifest wire shape (A4)

Frozen §5.1 wire shape for the capability manifest: ten field groups, loader rules, and the
published-version content-hash registry. Later slices (C1, C2, C5, C6, E7, H1, H5) **consume**
this artifact — they extend, never rewrite these group names, field keys, or validation rules.

**Source of truth in code:** `ai-platform/src/manifest/index.ts` (`MANIFEST_FIELD_MANIFEST`,
`Manifest` type, `load`, `hashManifest`, `verifyPublishedRegistry`).

**Traces to:** spec **Freezes** entry; FR-001–FR-010.

---

## 1. Overview

A capability manifest is the platform's immutable declaration of an AI feature version. It is JSON
validated at build time by `load(json)` and materialises as a typed `Manifest` object whose
`interactionMode` is read-only for the life of that version.

Two load-bearing properties apply to every manifest:

- **Data, not code.** The manifest contributes no executable pipeline or client entry point; adding a
  capability that reuses existing context keys, routing policy, and validation rules requires no
  pipeline or client change.
- **Requirements only.** A manifest never names a provider or a model; the Routing group names
  requirements and policy refs, leaving target selection to the routing policy.

---

## 2. Wire encoding

Manifests are JSON objects. Each of the ten §5.1 field groups is a top-level key using the group
name verbatim (including spaces in `Context requirements` and `Prompt binding`). Field keys within
each group use camelCase as declared in `MANIFEST_FIELD_MANIFEST`.

A valid manifest MUST include all ten groups. Omitting a group or supplying a group with the wrong
shape causes `load()` to throw, naming the offending group.

---

## 3. Field groups

### 3.1 Identity

| Field key | Contents |
| --- | --- |
| `capabilityId` | Stable capability identifier (e.g. `clinic.visit_summary`). |
| `version` | Semantic version string for this capability build. |
| `title` | Human-readable title for discovery. |
| `lifecycleState` | One of `active`, `deprecated`, `retired`. |
| `successorId` | Capability id of the replacement version, or `null` when none. |

**Consumed by:** Capability resolver, clients (discovery).

### 3.2 Access

| Field key | Contents |
| --- | --- |
| `requiredCapabilityScope` | Scope token required on the caller's token. |
| `minimumPlanTier` | Minimum installation plan tier. |
| `allowedStaffRoles` | Staff roles permitted to invoke the capability. |
| `killSwitchFlag` | Boolean; when true the capability is disabled at request time. |

**Consumed by:** Identity and entitlement stages.

### 3.3 Interaction

| Field key | Contents |
| --- | --- |
| `interactionMode` | `single_shot` or `conversational`. **Optional on wire** — see §4. |
| `maxHistoryTurns` | **Conversational only.** Maximum transcript turns. |
| `maxContextRoundsPerTurn` | **Conversational only.** Maximum context-negotiation rounds per turn. |
| `transcriptSizeLimit` | **Conversational only.** Maximum transcript size in bytes or tokens. |

**Consumed by:** Protocol adapter, context validator, prompt composer.

### 3.4 Input

| Field key | Contents |
| --- | --- |
| `userIntentShape` | Shape of the user's intent payload. |
| `priorTurnShape` | Shape of prior-turn data; required for `conversational`. |
| `sizeLimits` | Input size bounds (e.g. `{ maxChars }`). |
| `allowedLanguages` | Permitted language codes. |

**Consumed by:** Protocol adapter, context validator.

### 3.5 Context requirements

An ordered array of context-key requirement objects:

| Field key | Contents |
| --- | --- |
| `key` | Context key in `domain.concept@vN` form (e.g. `visit.chief_complaint@v1`). |
| `required` | Whether the key must be present on submit. |
| `shapeRef` | Reference to the platform-published shape for this key. |
| `maxSize` | Maximum payload size for this key. |
| `freshnessHint` | Freshness expectation (e.g. `session`). |

For `conversational` capabilities, a **permitted key set** the assistant may request during a turn
is declared here instead of (or in addition to) static required keys — full conversational validation
is slice H1.

**Consumed by:** Context validator, client Context Resolver (§5.2).

### 3.6 Prompt binding

| Field key | Contents |
| --- | --- |
| `systemInstructionArtifactRef` | Reference to the system-instruction prompt artifact. |
| `businessRuleFragmentRefs` | References to business-rule fragment artifacts. |
| `contextRenderingTemplateRef` | Reference to the context-rendering template. |
| `outputFormatInstructionDerivationRule` | Rule for deriving output-format instructions from Output mode. |

**Consumed by:** Prompt composer.

### 3.7 Output

| Field key | Contents |
| --- | --- |
| `mode` | One of `prose`, `structured`, `structured_atomic`. |
| `outputSchemaRef` | Reference to the output schema, or `null` for prose. |
| `businessValidationRuleRefs` | References to business validation rules. |
| `repairPolicy` | `{ allowed: boolean, maxAttempts: number }` — whether and how often output repair may run. |

**Consumed by:** Validator, stream broker.

### 3.8 Routing

| Field key | Contents |
| --- | --- |
| `routingPolicyRef` | Reference to a versioned routing policy (independently deployable). |
| `requiredProviderFeatures` | Requirements object (e.g. `structuredOutput`, `contextWindow`, `language`) — never a provider or model name. |
| `latencyClass` | Latency tier (e.g. `standard`). |
| `degradedTierPolicy` | Policy when primary targets are unavailable (e.g. `fallback_chain`). |

**Consumed by:** Provider router.

**Forbidden keys:** any key matching `/provider|model/i` anywhere in the manifest tree, except the
allowlisted Routing key name `requiredProviderFeatures` (nested provider/model keys under it still
fail). Exact key-set equality per group also rejects extras such as `preferredProvider` or
`modelHint`. See §6.

### 3.9 Economics

| Field key | Contents |
| --- | --- |
| `maxInputTokens` | Per-request (per-turn for `conversational`) input token ceiling. |
| `maxOutputTokens` | Per-request output token ceiling. |
| `perRequestCostCeiling` | Maximum billable **tokens** per request (per turn for `conversational`): `estimatedInputTokens + maxOutputTokens` must not exceed it. Token-denominated, no currency (§13.6.2). |
| `quotaWeight` | Weight applied in quota accounting. |

For `conversational`, the per-request ceiling applies per turn; the conversation is bounded by
Interaction turn and round limits rather than by a running total.

**Consumed by:** Entitlement stage.

### 3.10 Governance

| Field key | Contents |
| --- | --- |
| `acceptanceMode` | One of `advisory_display`, `human_accept_required`, `auto_apply` (`auto_apply` disallowed for clinical content per A5). |
| `retentionClass` | Journal retention class for outputs of this capability. |
| `evalSuiteRef` | Reference to the eval suite guarding prompt and behaviour changes. |

**Consumed by:** Client, journal, CI.

---

## 4. Interaction mode default

When `interactionMode` is **omitted** from the Interaction group, `load()` resolves it to
`single_shot`. An omitted value is a valid default, not a malformed manifest.

`interactionMode` is the **only switch that changes a request's shape**. It is fixed for the life of
a capability version: `load()` returns a deeply frozen `Manifest`; runtime mutation throws (§5.7).

---

## 5. Conversational-only field rejection

On a `single_shot` manifest, the following Interaction fields MUST NOT be present:

| Field key | Meaning |
| --- | --- |
| `maxHistoryTurns` | Maximum transcript turns. |
| `maxContextRoundsPerTurn` | Maximum context-negotiation rounds per turn. |
| `transcriptSizeLimit` | Maximum transcript size. |

If any of these fields appear while `interactionMode` is `single_shot` (explicit or defaulted),
`load()` throws with `Conversational-only field rejected on single_shot: <field>`. There is no
silent-stripping path.

Full validation of conversational field **numeric bounds** remains slice H1. Vocabulary membership
of `permittedKeySet` entries is the H1 content rule co-located in this loader (H1 Consumes A4).

Content enums validated at load time: `Identity.lifecycleState` ∈ {`active`,`deprecated`,`retired`};
`Output.mode` ∈ {`prose`,`structured`,`structured_atomic`}; `Governance.acceptanceMode` ∈
{`advisory_display`,`human_accept_required`,`auto_apply`}.

---

## 6. Never-names-provider-or-model rule

The manifest MUST name requirements and policy references only. `load()` walks every object key in
the manifest tree and rejects any key matching `/provider|model/i`, except the allowlisted Routing
key name `requiredProviderFeatures`. Nested keys such as `requiredProviderFeatures.model` still fail.

Exact key-set equality against `MANIFEST_FIELD_MANIFEST` additionally rejects unknown keys in every
group (e.g. `preferredProvider`, `modelHint`).

| Example forbidden key | Rejection |
| --- | --- |
| `provider` / `model` | denylist or exact-key failure |
| `preferredProvider` | exact-key / denylist failure on Routing |
| `modelHint` | exact-key / denylist failure on Prompt binding |

Provider and model selection is owned by the routing policy, not the manifest.

---

## 7. Published-version content-hash registry

### 7.1 Immutability rule

A published capability version is immutable. Any semantically meaningful edit to a published version
MUST produce a new version — never an in-place mutation (§5.1, §5.7).

### 7.2 Registry mechanism

The build enforces immutability through a checked-in append-only registry mapping
`(capability_id, version)` → manifest content hash:

1. **Published tree** — JSON manifests under `ai-platform/manifests/published/` and
   `ai-platform/manifests/published-registry.json`.
2. **`hashManifest(json)`** — async WebCrypto SHA-256 over the canonical manifest encoding
   (sorted object keys, recursive); returns 64 lowercase hex characters.
3. **`verifyPublishedRegistry(entries, registry)`** — for each `PublishedRegistryEntry`
   `{ capabilityId, version, hash }`, looks up `registry[`${capabilityId}@${version}`]` and throws
   if the on-disk hash differs from the registry entry.
4. **`verifyManifestTree(io)`** / **`npm run verify-manifests`** — loads every published file,
   hashes it, and runs the registry check. Wired into `npm test`.

A hash mismatch means an in-place edit to a published version and **fails the build** (T-A4-12,
T-A4-23; CI gate per §13.5).

### 7.3 Registry key format

```
<capabilityId>@<version>
```

Example: `clinic.visit_summary@1.0.0`

---

## 8. Loader export surface

`ai-platform/src/manifest/` exports:

| Export | Role |
| --- | --- |
| `load(json)` | Validate and return a deeply frozen typed `Manifest`. |
| `hashManifest(json)` | Async WebCrypto SHA-256 content hash for registry checks. |
| `verifyPublishedRegistry(entries, registry)` | Assert on-disk hashes match published entries. |
| `verifyManifestTree(io)` | Build gate over checked-in published manifests + registry. |
| `Manifest` | TypeScript type for the loaded manifest. |
| `MANIFEST_FIELD_GROUPS` | Ordered list of the ten group names. |
| `MANIFEST_FIELD_MANIFEST` | Field-key manifest per group (schema-as-data). |

The internal validator is not exported. No pipeline wiring, request handler, or client entry point
is exposed from this module (T-A4-15).
