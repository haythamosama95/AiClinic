# AI Platform Data Journey — Stage 5 — Routing policy (D1 index + R2 document)

## Table of Contents

1. [Plain language](#1-plain-language)
2. [Metaphor](#2-metaphor)
3. [Manifest link](#3-manifest-link)
  - [Field presence key](#31-field-presence-key)
  - [Routing inputs — manifest → router](#32-routing-inputs-manifest-router)
  - [Complete specimen (visit summary)](#33-complete-specimen-visit-summary)
  - [Field-by-field reference — every group](#34-field-by-field-reference-every-group)
    - `[Identity](#341-identity)`
    - `[Access](#342-access)`
    - `[Interaction](#343-interaction)`
    - `[Input](#344-input)`
    - `[Context requirements](#345-context-requirements)`
    - `[Prompt binding](#346-prompt-binding)`
    - `[Output](#347-output)`
    - `[Routing](#348-routing)`
    - `[Economics](#349-economics)`
    - `[Governance](#3410-governance)`
  - [How manifest floors meet R2](#35-how-manifest-floors-meet-r2-requires) `requires`
4. [R2 document — every field](#4-r2-document-every-field)
  - [R2 object key](#41-r2-object-key)
  - [Complete document specimen](#42-complete-document-specimen)
  - [Document overview — what each block is for](#43-document-overview-what-each-block-is-for)
  - [Field-by-field reference](#44-field-by-field-reference)
    - [Identity header](#441-identity-header)
    - `defaults` [— policy-wide fallbacks](#442-defaults-policy-wide-fallbacks)
    - `rules[]` [— ordered routing rules](#443-rules-ordered-routing-rules)
      - `rules[].match` [— request filters](#4431-rulesmatch-request-filters)
      - `rules[].requires` [— capability requirement floor](#4432-rulesrequires-capability-requirement-floor)
      - `rules[].targets[]` [— one provider/model candidate](#4433-rulestargets-one-providermodel-candidate)
      - `targets[].features` [— target capability advertisement](#4434-targetsfeatures-target-capability-advertisement)
    - `overrides[]` [— per-installation exceptions](#444-overrides-per-installation-exceptions)
  - [Hardcoded, ignored, and wiring gaps](#45-hardcoded-ignored-and-wiring-gaps)
5. [D1](#5-d1-routing_policy-row-every-column) `routing_policy` [row — every column](#5-d1-routing_policy-row-every-column)
6. [Control endpoints](#6-control-endpoints)
  - [Greenfield bootstrap:](#60-greenfield-bootstrap) `npm run bootstrap:routing-policy`
  - [Publish:](#61-publish-post-controlrouting-policiespublish) `POST /control/routing-policies/publish`
  - [Canary:](#62-canary-post-canary) `POST …/canary`
  - [Promote:](#63-promote-post-promote) `POST …/promote`
  - [Rollback:](#64-rollback-post-rollback) `POST …/rollback`
7. [Router output (](#7-router-output-routingdecision-every-field)`RoutingDecision`[) — every field](#7-router-output-routingdecision-every-field)
8. [Routing failure paths (post-accept)](#8-routing-failure-paths-post-accept)
9. [Behavioral verification](#9-behavioral-verification)
  - [9.1 Setup](#91-setup)
  - [9.2 Coverage](#92-coverage)
  - [9.3 Ordered probes](#93-ordered-probes)
    - [9.3.1 Reset to a known policy state](#931-reset-to-a-known-policy-state)
    - [9.3.2 Who may call control APIs](#932-who-may-call-control-apis)
    - [9.3.3 Publish failure paths](#933-publish-failure-paths)
    - [9.3.4 First publish and storage inspection](#934-first-publish-and-storage-inspection)
    - [9.3.5 Duplicate publish leaves R2 unchanged](#935-duplicate-publish-leaves-r2-unchanged)
    - [9.3.6 Latency warning and unreferenced policy](#936-latency-warning-and-unreferenced-policy)
    - [9.3.7 Published policy is not served](#937-published-policy-is-not-served)
    - [9.3.8 Canary failure paths](#938-canary-failure-paths)
    - [9.3.9 Canary success and serving split](#939-canary-success-and-serving-split)
    - [9.3.10 Promote to active](#9310-promote-to-active)
    - [9.3.11 Rollback and version tie-break](#9311-rollback-and-version-tie-break)
    - [9.3.12 Manifest link and independent switches](#9312-manifest-link-and-independent-switches)
    - [9.3.13 Missing R2 document](#9313-missing-r2-document)
    - [9.3.14 Router identity schema and catch-all](#9314-router-identity-schema-and-catch-all)
    - [9.3.15 RoutingDecision on a routed request](#9315-routingdecision-on-a-routed-request)
    - [9.3.16 Match clauses and requirement floors](#9316-match-clauses-and-requirement-floors)
    - [9.3.17 Overrides and cost class](#9317-overrides-and-cost-class)
    - [9.3.18 Target exclusions and empty chain](#9318-target-exclusions-and-empty-chain)
    - [9.3.19 Provider kill switch failover](#9319-provider-kill-switch-failover)
    - [9.3.20 What this stage does not do](#9320-what-this-stage-does-not-do)
    - [9.3.21 Unreachable and operator-hostile paths](#9321-unreachable-and-operator-hostile-paths)

---



## 1. Plain language

Routing decides **which AI provider and model** handle a request. Three artifacts link together:

1. **Capability manifest** (bundled in the Worker) — each capability declares a `routingPolicyRef` (e.g. `routing/standard`) naming the playbook id only, plus request-side needs (languages, latency class, token ceiling).
2. **D1** `routing_policy` **row** — resolves that ref to an active version and an R2 `content_pointer`; tracks lifecycle (published, canary, active, superseded).
3. **R2 routing policy document** — the full playbook at that pointer: ordered `rules[]` with `match` clauses and provider `targets`.

At invoke time the router parses the manifest ref → loads the document via D1 + config cache → walks `rules[]` top to bottom until the first `match` passes (including `capability_ids`, tier, language, and other filters) → merges manifest requirements with the matched rule → applies installation `overrides` → emits the final target chain. The manifest picks **which playbook**; D1 picks **which version**; R2 defines **which providers to try**.

**Greenfield bring-up:** Worker boot and D1 migrations do **not** publish or activate a routing policy. For local/dev provisioning, run `npm run bootstrap:routing-policy` after migrations and `npm run dev` — it publishes the checked-in fixture `control/routing-policy/platform-default/1.json` (`standard@1`) and promotes it to `active`. See [§6.0](#60-greenfield-bootstrap). Stage 5 behavioral probes ([§9.3](#93-ordered-probes)) still start from an empty `routing_policy` table on purpose.

## 2. Metaphor

Think of **air traffic control** for AI requests:


| Artifact                        | File (example)                                                     | Metaphor                                                                                                                                                                                                                                                                                 |
| ------------------------------- | ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Capability manifest JSON**    | `manifests/published/clinic.visit_summary@1.0.0.json`              | The **flight plan** carried on every plane. It names the capability (`clinic.visit_summary`), states what the flight needs (language, latency, token limits), and points at a playbook id: `routingPolicyRef` → `routing/standard` (version is **not** in the ref — D1 picks it). Bundled in the Worker — not stored in the warehouse. |
| **D1** `routing_policy` **row** | *(no JSON file — a database row)*                                  | The **filing cabinet index card**: "playbook `standard` version `1` is **active**; full copy is at shelf `control/routing-policy/standard/1.json`." Also tracks canary rollouts and superseded versions.                                                                                 |
| **Routing policy JSON**         | `control/routing-policy/platform-default/1.json` → published to R2 | The **playbook in the warehouse** (R2): ordered rules for *when* to route, *minimum requirements*, and *which providers to try* in order. Published once via the control API; the repo file is only a fixture for operators — runtime reads R2 via the D1 pointer.                       |


**Flow:** the flight plan (capability JSON) says *which playbook* → the index card (D1) says *which version is live* → the warehouse copy (routing JSON in R2) says *which providers to use*.

## 3. Manifest link

The capability manifest is bundled JSON deployed with the Worker (`ai-platform/manifests/published/`). It is **not** in D1 or R2. The loader (`ai-platform/src/manifest/index.ts`, [../01-ai-platform.md §5.1](../01-ai-platform.md#51-capability-manifest) ten field groups) validates shape at build time; the invoke path resolves `capability_id@version` from the registry and reads the frozen object in memory.

**Routing role:** the manifest supplies (a) `routingPolicyRef` → which R2 playbook to load via D1, and (b) **requirement floors** merged with the matched rule's `requires` before target filtering. Other groups govern entitlement, context, prompts, and economics — not rule selection itself.

### 3.1 Field presence key


| Symbol             | Meaning                                                                                               |
| ------------------ | ----------------------------------------------------------------------------------------------------- |
| **group required** | Top-level group must exist in JSON                                                                    |
| **field required** | Key must appear in the group object                                                                   |
| **field optional** | Key may be omitted; loader applies a default                                                          |
| **nullable**       | Key required; value may be `null`                                                                     |
| **routing: ref**   | Feeds policy lookup (`routingPolicyRef` → D1 → R2)                                                    |
| **routing: match** | Feeds `rules[].match.`* comparison via `RouterContext`                                                |
| **routing: floor** | Merged with `rules[].requires`; filters `targets[]`                                                   |
| **routing: cost**  | Input to `effective_cost_class` (partially wired — see [§4.5](#45-hardcoded-ignored-and-wiring-gaps)) |
| **not routing**    | Consumed in earlier/later pipeline stages only                                                        |




### 3.2 Routing inputs — manifest → router


| Router input                              | Manifest source                                                                             | Routing stage use                       |
| ----------------------------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------- |
| `capabilityId`                            | `Identity.capabilityId`                                                                     | `match.capability_ids`                  |
| `installationId`                          | *(AAT — not manifest)*                                                                      | `match.installation_ids`                |
| `routingTier`                             | *(quota/admission — not manifest)*                                                          | `match.tiers`                           |
| `requirements.structured_output_required` | `Output.mode` (`!== "prose"`)                                                               | target feature filter                   |
| `requirements.min_context_window`         | `Routing.requiredProviderFeatures.contextWindow`                                            | target feature filter                   |
| `requirements.languages`                  | `Routing.requiredProviderFeatures.language`                                                 | `match.languages` + target filter       |
| `requirements.latency_class`              | `Routing.latencyClass`                                                                      | `match.latency_classes` + target filter |
| `manifestCostClass`                       | architectural cost ceiling *(not a separate published key today; hardcoded in invoke path)* | `match.cost_classes` + target filter    |
| `policyCacheKey`                          | `Routing.routingPolicyRef`                                                                  | D1 preload → R2 document                |


`routingPolicyRef` format: `routing/{policy_id}` (e.g. `routing/standard`). The invoke path looks up D1 by `policy_id` only; `routing_policy.status` (`canary` for cohort installations, else `active`) selects which version is served. A legacy `@v{n}` suffix is tolerated and stripped at parse time — it never pinned a version. To move a capability to playbook v2, operators publish and canary/promote in D1; the manifest ref is not edited.

### 3.3 Complete specimen (visit summary)

Checked-in file: `ai-platform/manifests/published/clinic.visit_summary@1.0.0.json`. The `shapeRef` below resolves to the bundled shape artifact `ai-platform/context/shapes/published/visit.chief_complaint@v1.json` (architecture §5.2 "Shape artifacts"); the manifest names the shape by id, it does not carry the field definitions.

```json
{
  "Identity": {
    "capabilityId": "clinic.visit_summary",
    "version": "1.0.0",
    "title": "Visit summary",
    "lifecycleState": "active",
    "successorId": null
  },
  "Access": {
    "requiredCapabilityScope": "ai.visit_summary",
    "minimumPlanTier": "standard",
    "allowedStaffRoles": ["clinician", "nurse"],
    "killSwitchFlag": false
  },
  "Interaction": {
    "interactionMode": "single_shot"
  },
  "Input": {
    "userIntentShape": "plain_text",
    "priorTurnShape": null,
    "sizeLimits": { "maxChars": 8000 },
    "allowedLanguages": ["en"]
  },
  "Context requirements": [
    {
      "key": "visit.chief_complaint@v1",
      "required": true,
      "shapeRef": "visit.chief_complaint@v1",
      "maxSize": 4096
    }
  ],
  "Prompt binding": {
    "systemInstructionArtifactRef": "clinic.visit_summary/system@v1",
    "businessRuleFragmentRefs": ["clinic.visit_summary/rules-visit-summary@v1"],
    "contextRenderingTemplateRef": "clinic.visit_summary/template-visit-summary@v1",
    "outputFormatInstructionDerivationRule": "derive_from_output_mode"
  },
  "Output": {
    "mode": "prose",
    "outputSchemaRef": null,
    "businessValidationRuleRefs": [],
    "repairPolicy": { "allowed": false, "maxAttempts": 0 }
  },
  "Routing": {
    "routingPolicyRef": "routing/standard",
    "requiredProviderFeatures": {
      "structuredOutput": false,
      "contextWindow": 32000,
      "language": "en"
    },
    "latencyClass": "standard",
    "degradedTierPolicy": "fallback_chain"
  },
  "Economics": {
    "maxInputTokens": 8000,
    "maxOutputTokens": 1024,
    "perRequestTokenCeiling": 9024,
    "quotaWeight": 1
  },
  "Governance": {
    "acceptanceMode": "advisory_display",
    "retentionClass": "diagnostic_30d",
    "evalSuiteRef": "evals/visit-summary@v1"
  }
}
```



### 3.4 Field-by-field reference — every group

All ten groups are **group required**. Keys marked **field required** must appear exactly once per group (no extra keys). Enum values enforced at load time are noted.

#### 3.4.1 `Identity`


| Field            | Presence                     | Type                                | Meaning                                                         | Routing                                     |
| ---------------- | ---------------------------- | ----------------------------------- | --------------------------------------------------------------- | ------------------------------------------- |
| `capabilityId`   | field required               | `string`                            | Stable capability name (wire `capability_id` must resolve here) | **routing: match** → `match.capability_ids` |
| `version`        | field required               | `string`                            | Semver of this manifest revision                                | not routing (registry lookup key)           |
| `title`          | field required               | `string`                            | Human label for ops/discovery                                   | not routing                                 |
| `lifecycleState` | field required               | `active` | `deprecated` | `retired` | Whether invoke is allowed                                       | not routing (capability resolve gate)       |
| `successorId`    | field required, **nullable** | `string` | `null`                   | Replacement capability when deprecated/retired                  | not routing                                 |




#### 3.4.2 `Access`


| Field                     | Presence       | Type       | Meaning                                                                                         | Routing                                                      |
| ------------------------- | -------------- | ---------- | ----------------------------------------------------------------------------------------------- | ------------------------------------------------------------ |
| `requiredCapabilityScope` | field required | `string`   | Staff scope token required on AAT                                                               | not routing (enforced at capability resolve / guard stage 5) |
| `minimumPlanTier`         | field required | `string`   | Lowest plan that may invoke                                                                     | not routing (entitlement gate)                               |
| `allowedStaffRoles`       | field required | `string[]` | Roles permitted; enforced at capability resolve / guard stage 5 when non-empty                  | not routing                                                  |
| `killSwitchFlag`          | field required | `boolean`  | Capability-level kill; `=== true` at capability resolve / guard stage 5 → `capability_disabled` | not routing                                                  |




#### 3.4.3 `Interaction`


| Field                     | Presence                                   | Type                             | Meaning                                 | Routing     |
| ------------------------- | ------------------------------------------ | -------------------------------- | --------------------------------------- | ----------- |
| `interactionMode`         | **field optional** (default `single_shot`) | `single_shot` | `conversational` | Single request vs multi-turn transcript | not routing |
| `maxHistoryTurns`         | field required **when conversational**     | positive `integer`               | Turn budget                             | not routing |
| `maxContextRoundsPerTurn` | field required **when conversational**     | positive `integer`               | Context rounds per turn                 | not routing |
| `transcriptSizeLimit`     | field required **when conversational**     | positive `integer`               | Max transcript bytes                    | not routing |




#### 3.4.4 `Input`


| Field              | Presence                     | Type              | Meaning                                       | Routing                                                                 |
| ------------------ | ---------------------------- | ----------------- | --------------------------------------------- | ----------------------------------------------------------------------- |
| `userIntentShape`  | field required               | `string`          | Expected shape of `userIntent` on wire        | not routing                                                             |
| `priorTurnShape`   | field required, **nullable** | `string` | `null` | Prior-turn shape for conversational mode      | not routing                                                             |
| `sizeLimits`       | field required               | object            | e.g. `{ "maxChars": 8000 }` ingress cap       | not routing                                                             |
| `allowedLanguages` | field required               | `string[]`        | Languages the capability accepts from clients | not routing (distinct from routing `requiredProviderFeatures.language`) |




#### 3.4.5 `Context requirements`

Shape depends on `interactionMode`:


| Mode             | Shape                             | Presence                                          |
| ---------------- | --------------------------------- | ------------------------------------------------- |
| `single_shot`    | `array` of entries                | **group required**; array may be empty            |
| `conversational` | `{ "permittedKeySet": string[] }` | **group required**; `permittedKeySet` may be `[]` |


Entry fields (single-shot array items):


| Field      | Presence       | Type      | Meaning                         | Routing     |
| ---------- | -------------- | --------- | ------------------------------- | ----------- |
| `key`      | field required | `string`  | A5 context key id               | not routing |
| `required` | field required | `boolean` | Must appear in invoke `context` | not routing |
| `shapeRef` | field required | `string`  | Validator shape reference → bundled artifact `context/shapes/published/{shapeRef}.json` | not routing |
| `maxSize`  | field required | number    | Max serialized bytes for key    | not routing |


**Schema note:** there is no `freshnessHint`. The loader rejects it as an extra key. Stale context is accepted by design (architecture §6.7.3); containment is the journal of exact context plus the advisory-output rule, not a per-key freshness gate.

#### 3.4.6 `Prompt binding`


| Field                                   | Presence       | Type       | Meaning                           | Routing                     |
| --------------------------------------- | -------------- | ---------- | --------------------------------- | --------------------------- |
| `systemInstructionArtifactRef`          | field required | `string`   | Prompt artifact ref               | not routing (compose stage) |
| `businessRuleFragmentRefs`              | field required | `string[]` | Rule fragment refs                | not routing                 |
| `contextRenderingTemplateRef`           | field required | `string`   | Template ref for context render   | not routing                 |
| `outputFormatInstructionDerivationRule` | field required | `string`   | How to derive format instructions | not routing                 |




#### 3.4.7 `Output`


| Field                        | Presence                     | Type                                         | Meaning                                       | Routing                                                            |
| ---------------------------- | ---------------------------- | -------------------------------------------- | --------------------------------------------- | ------------------------------------------------------------------ |
| `mode`                       | field required               | `prose` | `structured` | `structured_atomic` | Response shape contract                       | **routing: floor** → `structured_output_required` when not `prose` |
| `outputSchemaRef`            | field required, **nullable** | `string` | `null`                            | JSON schema ref when structured               | not routing                                                        |
| `businessValidationRuleRefs` | field required               | `string[]`                                   | Post-generation validation refs               | not routing                                                        |
| `repairPolicy`               | field required               | object                                       | `{ allowed, maxAttempts }` repair loop policy | not routing                                                        |


> `requiredProviderFeatures.structuredOutput` is declared in `Routing` but the invoke router derives structured-output demand from `Output.mode`, not that flag (see `worker.ts`).



#### 3.4.8 `Routing`


| Field                      | Presence       | Type     | Meaning                                                          | Routing                                 |
| -------------------------- | -------------- | -------- | ---------------------------------------------------------------- | --------------------------------------- |
| `routingPolicyRef`         | field required | `string` | Playbook id reference resolved via D1 (`routing/{id}`); version is chosen by D1 `status`, not the ref | **routing: ref**                        |
| `requiredProviderFeatures` | field required | object   | Minimum provider capability floor from the capability side       | **routing: floor** (see nested table)   |
| `latencyClass`             | field required | `string` | Expected latency tier (e.g. `"interactive"`, `"standard"`)       | **routing: match** + **routing: floor** |
| `degradedTierPolicy`       | field required | `string` | Policy when `routingTier === "degraded"` (e.g. `fallback_chain`) | not routing today (schema only)         |


Nested `requiredProviderFeatures` (conventional keys; loader does not enforce exact nested keys beyond forbidding provider/model names):


| Field              | Presence     | Type      | Meaning                                             | Routing                                                                |
| ------------------ | ------------ | --------- | --------------------------------------------------- | ---------------------------------------------------------------------- |
| `structuredOutput` | conventional | `boolean` | Documented provider need for JSON/structured output | **not read at invoke** — use `Output.mode`                             |
| `contextWindow`    | conventional | `integer` | Minimum context window in tokens                    | **routing: floor** → merged with `rules[].requires.min_context_window` |
| `language`         | conventional | `string`  | Primary language the capability requires            | **routing: match** + **routing: floor** → `requirements.languages`     |




#### 3.4.9 `Economics`


| Field                    | Presence       | Type   | Meaning                                                                                                                                                                     | Routing                                                          |
| ------------------------ | -------------- | ------ | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------- |
| `maxInputTokens`         | field required | number | Token budget for input side                                                                                                                                                 | not routing (token pre-flight)                                   |
| `maxOutputTokens`        | field required | number | Token budget for output side                                                                                                                                                | not routing                                                      |
| `perRequestTokenCeiling` | field required | number | Combined **token** ceiling per request: `estimatedInputTokens + maxOutputTokens` must not exceed it. Token-denominated; the preflight never converts to currency (§13.6.2). | **routing: cost** (architectural; maps to cost class when wired) |
| `quotaWeight`            | field required | number | Weight for quota/admission accounting                                                                                                                                       | not routing                                                      |


**Schema note:** the canonical Economics field is `perRequestTokenCeiling`. Previously published manifests used `perRequestCostCeiling` for the same token comparison. The loader (`ai-platform/src/manifest/index.ts`) still accepts that legacy key as a compatibility alias and normalizes it to `perRequestTokenCeiling`. Capability manifests do not carry a numeric `schema_version` header; this is a field-name revision of the Economics group. Public name going forward is tokens, not cost.

#### 3.4.10 `Governance`


| Field            | Presence       | Type                                                        | Meaning                               | Routing     |
| ---------------- | -------------- | ----------------------------------------------------------- | ------------------------------------- | ----------- |
| `acceptanceMode` | field required | `advisory_display` | `human_accept_required` | `auto_apply` | How clinic staff must treat AI output | not routing |
| `retentionClass` | field required | `diagnostic_Nd` (`N` = 1–90)                                | Journal retention horizon             | not routing |
| `evalSuiteRef`   | field required | `string`                                                    | Eval harness reference                | not routing |




### 3.5 How manifest floors meet R2 `requires`

After rule selection, the router calls `mergeRequirementFloors(manifest requirements, matchedRule.requires)`:


| Dimension                    | Merge rule                                                                                         |
| ---------------------------- | -------------------------------------------------------------------------------------------------- |
| `structured_output_required` | OR — either manifest (`Output.mode`) or rule `requires.structured_output` forces structured output |
| `min_context_window`         | `Math.max(manifest contextWindow, rule requires.min_context_window)`                               |
| `languages`                  | **Union** — rule can add languages, not remove manifest ones                                       |
| `latency_class`              | From manifest only; compared to each target's `features.latency_class`                             |


See [§4.4](#44-field-by-field-reference) `rules[].requires` and [§4.5](#45-hardcoded-ignored-and-wiring-gaps) for remaining wiring gaps (`manifestCostClass`, entitlement cap). `routingTier` is live: invoke uses `routingTierFromAdmission` so `match.tiers` agrees with the journaled `ai_request.routing_tier`.

## 4. R2 document — every field

Canonical types: `ai-platform/src/router/index.ts` (`RoutingPolicyDocument`, lines 101–161).
Frozen contract: `specs/029-provider-port-routing/contracts/routing-decision.md` §2.

### 4.1 R2 object key

**Key:** `control/routing-policy/{policy_id}/{version}.json`

Written once at publish (`control/routing-policy.ts`); the D1 `routing_policy.content_pointer`
column stores this key. The config cache loads the JSON at preload time and attaches it as
`row.document` — the router never reads R2 on the hot path.

### 4.2 Complete document specimen

The specimen below shows **every field the router understands**, including every optional key
and schema-retained keys (`defaults.cost_class`, `defaults.max_parallel_attempts`,
`rules[].max_parallel_attempts`) that existing R2 documents still carry but the router ignores.
Placeholders in angle brackets must be replaced with real values. In production you normally use
**one** override mechanism per installation (not all three at once); the specimen stacks them so
nothing is hidden. `"interactive"` in `match.latency_classes` and target `features.latency_class`
is an **illustrative** example, not the checked-in production fixture (that fixture uses `"standard"`).

```json
{
  "schema_version": 1,
  "policy_id": "standard",
  "policy_version": 1,
  "defaults": {
    "cost_class": "standard",
    "max_parallel_attempts": 1
  },
  "rules": [
    {
      "rule_id": "visit-summary-standard",
      "match": {
        "capability_ids": ["clinic.visit_summary"],
        "installation_ids": ["<installation-uuid>"],
        "cost_classes": ["standard", "premium"],
        "tiers": ["standard", "degraded"],
        "languages": ["en"],
        "latency_classes": ["interactive"]
      },
      "requires": {
        "structured_output": false,
        "min_context_window": 32000,
        "languages": ["en"]
      },
      "targets": [
        {
          "provider_id": "deepseek",
          "model_id": "deepseek-v4-flash",
          "features": {
            "structured_output": true,
            "min_context_window": 128000,
            "languages": ["en"],
            "latency_class": "interactive",
            "cost_class": "standard"
          },
          "max_attempts": 2,
          "timeout_ms": 30000
        }
      ],
      "max_parallel_attempts": 1
    },
    {
      "rule_id": "catch-all",
      "match": {
        "capability_ids": [],
        "installation_ids": [],
        "cost_classes": [],
        "tiers": [],
        "languages": [],
        "latency_classes": []
      },
      "requires": {
        "structured_output": false,
        "min_context_window": 0,
        "languages": []
      },
      "targets": [
        {
          "provider_id": "deepseek",
          "model_id": "deepseek-v4-flash",
          "features": {
            "structured_output": true,
            "min_context_window": 128000,
            "languages": ["en"],
            "latency_class": "interactive",
            "cost_class": "standard"
          },
          "max_attempts": 2,
          "timeout_ms": 30000
        },
        {
          "provider_id": "gemini",
          "model_id": "gemini-3.5-flash",
          "features": {
            "structured_output": true,
            "min_context_window": 128000,
            "languages": ["en"],
            "latency_class": "interactive",
            "cost_class": "standard"
          },
          "max_attempts": 2,
          "timeout_ms": 30000
        }
      ],
      "max_parallel_attempts": 1
    }
  ],
  "overrides": [
    {
      "installation_id": "<installation-uuid>",
      "exclude_providers": ["gemini"],
      "pin_target": {
        "provider_id": "deepseek",
        "model_id": "deepseek-v4-flash"
      },
      "force_cost_class": "economy"
    }
  ]
}
```

**Field presence key**


| Symbol          | Meaning                                                         |
| --------------- | --------------------------------------------------------------- |
| always present  | Key must appear in every published document; router reads it    |
| optional key    | May be omitted; router treats omission as wildcard or fallback  |
| schema-retained | Must be present in JSON but router ignores the value at runtime |



| Path                                            | Presence                                                                                              | Field meaning and allowed values                                                                                                                                                                                                 |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `schema_version`                                | always present                                                                                        | Document JSON **format** version. `integer`; today only `1` is accepted (`unsupported_schema_version` otherwise). Independent of `policy_version`.                                                                           |
| `policy_id`                                     | always present                                                                                        | Short playbook name. `string` (e.g. `"standard"`). Must equal the D1 `routing_policy.policy_id` row and the publish URL; manifest ref `routing/standard` → `standard`.                                                        |
| `policy_version`                                | always present                                                                                        | Integer playbook revision. `integer` (e.g. `1`). Must equal D1 `routing_policy.version` and the publish URL.                                                                                                          |
| `defaults`                                      | always present                                                                                        | Policy-wide fallback object. Present in every document; most keys are schema-retained only (see below).                                                                                                                            |
| `defaults.cost_class`                           | schema-retained                                                                                       | Placeholder cost tier for document-shape parity. `economy` \| `standard` \| `premium`. **Ignored at runtime** — effective cost class comes from manifest ceiling, entitlement cap, and optional `force_cost_class`.              |
| `defaults.max_parallel_attempts`                | schema-retained                                                                                       | Placeholder parallel-attempt cap. `integer` (e.g. `1`). **Ignored at runtime** — invocation walks `chain[]` sequentially.                                                                                                        |
| `rules`                                         | always present (non-empty)                                                                            | Ordered routing rules; **first match wins**. Non-empty `array`. Last rule must be a catch-all (empty `match` or all match lists empty/absent).                                                                                   |
| `rules[].rule_id`                               | always present                                                                                        | Stable ops label copied to `routing_decision.rule_id`. `string` (e.g. `"catch-all"`, `"visit-summary-standard"`). Uniqueness not enforced at runtime.                                                                            |
| `rules[].match`                                 | always present (may be `{}`)                                                                          | **When** this rule applies. `object`; `{}` or all-empty clauses = wildcard (matches any request).                                                                                                                                |
| `rules[].match.capability_ids`                  | optional key                                                                                          | Capability allow-list. `string[]` of capability ids (e.g. `["clinic.visit_summary"]`). Omitted or `[]` = any capability.                                                                                                       |
| `rules[].match.installation_ids`                | optional key                                                                                          | Clinic installation allow-list. `string[]` of installation UUIDs. Omitted or `[]` = any installation.                                                                                                                            |
| `rules[].match.cost_classes`                    | optional key                                                                                          | Effective cost-class allow-list. `economy` \| `standard` \| `premium` in `CostClass[]`. Omitted or `[]` = any effective cost class.                                                                                              |
| `rules[].match.tiers`                           | optional key                                                                                          | Routing tier allow-list. `"standard"` \| `"degraded"` in `string[]`. `degraded` is set server-side (quota soft threshold); clients never send it. Omitted or `[]` = any tier.                                                      |
| `rules[].match.languages`                       | optional key                                                                                          | Language allow-list tested against manifest languages. `string[]` (e.g. `["en"]`). Request must need every language in the list. Omitted or `[]` = any.                                                                          |
| `rules[].match.latency_classes`                 | optional key                                                                                          | Latency tier allow-list compared to manifest `Routing.latencyClass`. `string[]` (e.g. `"standard"`, `"interactive"`). Omitted or `[]` = any.                                                                                     |
| `rules[].requires`                              | always present                                                                                        | **Minimum capability floor** for this rule. `object`; merged with manifest `requiredProviderFeatures` before target filtering (stricter wins).                                                                                    |
| `rules[].requires.structured_output`            | always present                                                                                        | Whether structured/JSON output is required. `boolean`. OR-merged with manifest (`Output.mode !== "prose"`). Either side `true` forces structured output.                                                                       |
| `rules[].requires.min_context_window`           | always present                                                                                        | Minimum context window in tokens. `integer` ≥ `0`. `Math.max` with manifest `contextWindow`. `0` = no extra floor from this rule.                                                                                                |
| `rules[].requires.languages`                  | always present                                                                                        | Extra required languages unioned into the manifest set. `string[]`; `[]` = rule adds none. Targets must support every merged language.                                                                                             |
| `rules[].targets`                               | always present                                                                                        | **Ordered fallback chain** for this rule. `array` of provider/model candidates; invocation walks ordinals sequentially until success or exhaustion. May become empty after filtering → `provider_unavailable`.                     |
| `rules[].targets[].provider_id`                 | always present                                                                                        | Wired provider adapter id. `string` (e.g. `"deepseek"`, `"gemini"`). Active kill-switch row `provider:{id}` excludes this target at runtime.                                                                                       |
| `rules[].targets[].model_id`                    | always present                                                                                        | **Pinned** model version (never a floating alias). `string` (e.g. `"deepseek-v4-flash"`). Passed through to `chain[].model_id` and `ai_attempt`.                                                                               |
| `rules[].targets[].features`                    | always present                                                                                        | What this target **claims** it can do — compared against merged requirements and manifest `latency_class`. `object` with the five fields below.                                                                                  |
| `rules[].targets[].features.structured_output`  | always present                                                                                        | Whether this model supports structured/JSON output. `boolean`. Excluded with `feature_unsupported` when merged requirements demand structured output.                                                                             |
| `rules[].targets[].features.min_context_window` | always present in a well-formed document; missing/non-numeric at request time → `feature_unsupported` | Largest context window this model claims, in tokens. Positive `integer`. Must be finite and ≥ merged `min_context_window`, else `context_window_too_small` or `feature_unsupported`.                                           |
| `rules[].targets[].features.languages`          | always present in a well-formed document; missing/non-array at request time → `feature_unsupported`   | Languages this target supports. `string[]` (e.g. `["en"]`). Must include every merged required language, else `language_unsupported` or `feature_unsupported`.                                                                 |
| `rules[].targets[].features.latency_class`      | always present                                                                                        | Model latency tier; must **equal** manifest `latency_class` exactly. `string` (e.g. `"standard"`, `"interactive"`). Mismatch → `feature_unsupported`.                                                                          |
| `rules[].targets[].features.cost_class`         | always present in a well-formed document; missing/unknown at request time → `feature_unsupported`     | Model price tier. `economy` \| `standard` \| `premium`. Known class above `effective_cost_class` → `cost_class_excluded`; missing/typo → `feature_unsupported`. Order: economy < standard < premium.                              |
| `rules[].targets[].max_attempts`                | always present                                                                                        | Max retries for **this** target before advancing to the next chain ordinal. Positive `integer` (e.g. `2`).                                                                                                                       |
| `rules[].targets[].timeout_ms`                  | always present                                                                                        | Per-attempt timeout for this target. Positive `integer` in milliseconds (e.g. `30000`).                                                                                                                                          |
| `rules[].max_parallel_attempts`                 | schema-retained                                                                                       | Per-rule parallel-attempt placeholder. `integer`. **Ignored at runtime** — not copied onto `routing_decision`.                                                                                                                   |
| `overrides`                                     | always present (may be `[]`)                                                                          | Per-installation exceptions applied **after** rule selection, **before** feature filtering. `array`; may be empty `[]`.                                                                                                          |
| `overrides[].installation_id`                   | always present on each override object                                                                | Clinic installation this override applies to. UUID `string`. Only the first matching entry is used.                                                                                                                             |
| `overrides[].exclude_providers`                 | optional key                                                                                          | Drop targets whose `provider_id` is listed. `string[]` of provider ids (e.g. `["gemini"]`). Omitted = no exclusions. Recorded as `installation_excluded`.                                                                        |
| `overrides[].pin_target`                        | optional key                                                                                          | Keep exactly one provider+model pair; all other targets in the rule are excluded. `object` with `provider_id` and `model_id`. If pin is absent from the rule chain, chain becomes empty.                                         |
| `overrides[].pin_target.provider_id`            | required when `pin_target` is present                                                                 | Provider id of the pinned target. `string`; must match a `targets[].provider_id` in the matched rule.                                                                                                                            |
| `overrides[].pin_target.model_id`               | required when `pin_target` is present                                                                 | Model id of the pinned target. `string`; must match a `targets[].model_id` in the matched rule.                                                                                                                                  |
| `overrides[].force_cost_class`                  | optional key                                                                                          | Caps effective cost class for this installation (third input to the three-source minimum). `economy` \| `standard` \| `premium`. Omitted = no installation cap.                                                                  |


> `defaults.cost_class` **and** `defaults.max_parallel_attempts` **— safe to remove.** The router
> never reads either field; deleting them from the TypeScript type, test fixtures, ops seed, and
> docs would not change routing behavior. Existing R2 objects that still include them need no
> migration (extra keys are ignored). A coordinated cleanup is required — not a one-line router
> change. `max_parallel_attempts` is also omitted from `RoutingDecision` and is not persisted.

Checked-in production fixture (catch-all only, no overrides):
`ai-platform/control/routing-policy/platform-default/1.json`.
On-disk directory name is historical; the document identity is `policy_id: "standard"` /
`policy_version: 1`. Both targets advertise `latency_class: "standard"` so they match published
`clinic.visit_summary@1.0.0` (`routingPolicyRef: "routing/standard"`, `latencyClass: "standard"`).
Publish writes R2 at `control/routing-policy/{policy_id}/{version}.json` derived from the document's identity fields, not the repo path.

Sibling platform config (not part of this R2 document, never client-visible): the versioned
price table `ai-platform/control/pricing/platform-default/1.json` is bundled into the Worker and
used only after the provider responds. Preflight stays token-only. See [Stage 11](13-stage-11-terminal-settlement.md).

### 4.3 Document overview — what each block is for

Think of the document as a **playbook the router reads top to bottom once per request**. It does not
call providers; it produces a `routing_decision` — an ordered chain of provider+model targets plus an
audit trail of exclusions. The large picture has four layers:

```mermaid
flowchart TD
  A["Identity header<br/>schema_version · policy_id · policy_version"] --> B["defaults<br/>policy-wide fallbacks"]
  B --> C["rules[]<br/>first match wins → targets chain"]
  C --> D["overrides[]<br/>per-installation tweaks"]
  D --> E["routing_decision<br/>chain + excluded + metadata"]
```




| Block                                                                 | One-line responsibility                                                                                   | Router step                                                         |
| --------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| **Identity header** (`schema_version`, `policy_id`, `policy_version`) | Proves this JSON is the playbook the D1 row points at                                                     | `validatePolicyDocument` — reject wrong format or identity mismatch |
| `defaults`                                                            | Schema-retained placeholders (`cost_class`, `max_parallel_attempts`)                                      | **Ignored at runtime** — neither field is read                      |
| `rules[]`                                                             | The routing logic: *when* (match) → *minimum needs* (requires) → *try these providers in order* (targets) | `.find()` first matching rule; last rule must be catch-all          |
| `overrides[]`                                                         | Per-clinic exceptions after a rule is chosen                                                              | Narrow the matched rule's target list; optionally cap cost class    |


**How a request walks the document** (implemented in `selectCandidateChain`, `router/index.ts`):

1. Load document from config cache (preloaded from D1 `content_pointer` → R2).
2. Validate identity and catch-all invariant.
3. Find `overrides[]` entry for this `installation_id` (if any).
4. Compute **effective cost class** from manifest ceiling + entitlement cap + optional `force_cost_class` (not from `defaults.cost_class`).
5. Walk `rules[]` in order; first rule whose `match` passes is selected.
6. Apply installation override (`exclude_providers`, `pin_target`) to that rule's `targets`.
7. Merge `requires` with manifest requirements; filter targets by features, kill switches, and cost class. Active `provider:<id>` kill switches arrive as `RouterContext.killedProviderIds` (collected at guard stage 5 from the policy's named providers). Those targets are excluded with `reason_code: kill_switch`; remaining targets stay in document order so traffic fails over. A provider kill switch does not 503 the capability.
8. Emit `routing_decision` with chain ordinals and exclusions (no `max_parallel_attempts`). Persist that JSON onto the existing `ai_request` row (`persistRoutingDecision`) so support can answer "why did this request go to model X?" from the ledger.

The manifest supplies the **request-side** inputs (`capabilityId`, `routingTier`, language, context
window, latency class). The document supplies the **provider-side** chain. Neither names the other
directly — the router joins them at runtime.

### 4.4 Field-by-field reference

Each field below states what it holds, how the router uses it, and how it fits the large picture.

#### 4.4.1 Identity header


| Field            | Type      | Role in the large picture                                                                                                                                                                               |
| ---------------- | --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `schema_version` | `integer` | Document **format** version (today only `1` is accepted). Independent of `policy_version` — you can publish policy v2 that still uses schema v1. Rejected with `unsupported_schema_version` if unknown. |
| `policy_id`      | `string`  | Short playbook name (e.g. `standard`). Must equal the D1 `routing_policy.policy_id` row and the manifest ref (`routing/standard` → `standard`). Mismatch → `policy_identity_mismatch`.               |
| `policy_version` | `integer` | Integer playbook revision (e.g. `1`). Must equal D1 `routing_policy.version`. Enables rollback by activating a different row without editing R2.                                             |




#### 4.4.2 `defaults` — policy-wide fallbacks


| Field                            | Type                               | Role in the large picture                                                                                                                                                                                                                              |
| -------------------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `defaults.cost_class`            | `economy` | `standard` | `premium` | **Schema-retained only** — present for [§4.3.7](../01-ai-platform.md#437-provider-router-and-policy-engine) table parity. `resolveEffectiveCostClass` never reads it. See [§4.5](#45-hardcoded-ignored-and-wiring-gaps).                               |
| `defaults.max_parallel_attempts` | `integer`                          | **Schema-retained only** — ignored. Invocation walks `chain[]` sequentially; parallel racing is not implemented (token spend is the dominant cost, [§13.6](../01-ai-platform.md#136-cost-and-performance-budget)). Not copied onto `routing_decision`. |




#### 4.4.3 `rules[]` — ordered routing rules

The array is evaluated **top to bottom**; the first matching rule wins. The **last** rule must be
a catch-all (empty `match` or all match lists empty/absent) — enforced at router time
(`missing_catch_all`).


| Field                           | Type                | Role in the large picture                                                                                                                                                                                 |
| ------------------------------- | ------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `rules[].rule_id`               | `string`            | Stable ops label (e.g. `catch-all`). Copied to `routing_decision.rule_id` and persisted on `ai_request.routing_decision` so support can answer "which rule fired?" Uniqueness is not enforced at runtime. |
| `rules[].match`                 | object              | **When** this rule applies. See match clauses below. Empty object `{}` = wildcard (matches any request).                                                                                                  |
| `rules[].requires`              | object              | **Minimum capability floor** merged with manifest requirements before target filtering. See requires fields below.                                                                                        |
| `rules[].targets`               | array               | **Ordered fallback chain** for this rule. Invocation walks ordinals **sequentially** until success or exhaustion. May be empty after filtering → `provider_unavailable`.                                  |
| `rules[].max_parallel_attempts` | `integer`, optional | **Schema-retained only** — ignored. Omitted or present, the walk stays sequential. Not copied onto `routing_decision`.                                                                                    |




##### 4.4.3.1 `rules[].match` — request filters

All six clause keys are **optional**. Omitted key, empty array `[]`, or absent clause = wildcard for
that dimension. When a clause is **non-empty**, the request must satisfy it.


| Field                    | Type                                    | Role in the large picture                                                                                                                                                                                                                                                                                         |
| ------------------------ | --------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `match.capability_ids`   | `string[]`, optional                    | Allow-list of capability ids (e.g. `clinic.visit_summary`). Request `capabilityId` must be in the list. Wildcard when omitted/`[]`.                                                                                                                                                                               |
| `match.installation_ids` | `string[]`, optional                    | Allow-list of clinic installation UUIDs. Request `installationId` must be in the list. Enables per-clinic routing rules without a separate document.                                                                                                                                                              |
| `match.cost_classes`     | `CostClass[]`, optional                 | Allow-list of **effective** cost classes (computed before rule matching). Lets you write different target chains for economy vs premium effective tiers.                                                                                                                                                          |
| `match.tiers`            | `"standard"` | `"degraded"`[], optional | Allow-list of routing tiers. `degraded` is set server-side when quota soft threshold is crossed — never sent by the client (ingress ignores `routing_tier` / `degraded` / `degraded_notice` body keys via empty `ADAPTER_ROUTING_BODY_FIELDS`). Enables separate degraded-tier chains (see soft-threshold tests). |
| `match.languages`        | `string[]`, optional                    | Allow-list tested against manifest languages. Request must need **every** language in the rule's list (subset check via `matchAllLanguages`).                                                                                                                                                                     |
| `match.latency_classes`  | `string[]`, optional                    | Allow-list of latency classes. Compared to manifest `Routing.latencyClass` (e.g. `"interactive"`).                                                                                                                                                                                                                |




##### 4.4.3.2 `rules[].requires` — capability requirement floor

Merged with manifest `requiredProviderFeatures` via `mergeRequirementFloors`. The stricter value
wins on each axis; languages are **unioned** (rule can only add languages, not remove manifest ones).


| Field                         | Type       | Role in the large picture                                                                                                                                                      |
| ----------------------------- | ---------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `requires.structured_output`  | `boolean`  | If `true`, only targets with `features.structured_output: true` survive filtering. OR-merged with manifest: either side `true` forces structured output.                       |
| `requires.min_context_window` | `integer`  | Minimum context window in tokens. `Math.max` with manifest `contextWindow`. Targets below this are excluded (`context_window_too_small`). `0` = no extra floor from this rule. |
| `requires.languages`          | `string[]` | Extra languages unioned into the required set. `[]` = rule adds none. Targets must support every merged language (`language_unsupported` if not).                              |




##### 4.4.3.3 `rules[].targets[]` — one provider/model candidate

Each entry is one step in the fallback chain. The capability layer also reads `provider_id` from all
targets to resolve wired providers (`capability/index.ts`); other target fields are ignored there.


| Field                    | Type      | Role in the large picture                                                                                                                     |
| ------------------------ | --------- | --------------------------------------------------------------------------------------------------------------------------------------------- |
| `targets[].provider_id`  | `string`  | Provider adapter id wired in the Worker (`deepseek`, `gemini`, …). Kill-switch rows keyed `provider:{id}` can exclude this target at runtime. |
| `targets[].model_id`     | `string`  | **Pinned** model version (contract R-4 — never a floating alias). Passed through to `chain[].model_id` and `ai_attempt`.                      |
| `targets[].features`     | object    | What this target **claims** it can do — compared against merged requirements. See features below.                                             |
| `targets[].max_attempts` | `integer` | Max retries for **this** target before advancing to the next chain ordinal. Passed to invocation as `chain[].max_attempts`.                   |
| `targets[].timeout_ms`   | `integer` | Per-attempt timeout in milliseconds for this target. Passed to invocation as `chain[].timeout_ms`.                                            |




##### 4.4.3.4 `targets[].features` — target capability advertisement


| Field                         | Type                               | Role in the large picture                                                                                                                                                                                                             |
| ----------------------------- | ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `features.structured_output`  | `boolean`                          | Whether this model supports structured/JSON output. Excluded with `feature_unsupported` when merged requirements demand structured output.                                                                                            |
| `features.min_context_window` | `integer`                          | Largest context window this model claims. Must be a finite number ≥ merged `min_context_window` or excluded (`context_window_too_small`). Missing or non-numeric → `feature_unsupported` (fail closed).                               |
| `features.languages`          | `string[]`                         | Languages this target supports. Must be an array that includes **every** merged required language (`language_unsupported` if not). Missing or non-array → `feature_unsupported` (fail closed; does not throw).                        |
| `features.latency_class`      | `string`                           | Must **equal** manifest `latency_class` exactly. Mismatch or missing → `feature_unsupported` (no distinct latency `reason_code` in the frozen enum).                                                                                  |
| `features.cost_class`         | `economy` | `standard` | `premium` | Target's price tier. A known class **higher** than `effective_cost_class` is excluded (`cost_class_excluded`). Missing or unknown (e.g. typo `"standrd"`) → `feature_unsupported` (fail closed). Order: economy < standard < premium. |


**Malformed target features fail closed.** Publish still does not fully validate target shape ([§4.5](#45-hardcoded-ignored-and-wiring-gaps)); `filterTargets` is the request-path defense. A missing or unknown `min_context_window`, `cost_class`, or `languages` excludes **that** target with `feature_unsupported`. A well-formed sibling stays in the chain. Declared-but-insufficient values keep their distinct codes (`context_window_too_small`, `language_unsupported`, `cost_class_excluded`). Latency already compared with exact `!==`.

#### 4.4.4 `overrides[]` — per-installation exceptions

Matched by `installation_id` on the request. Applied **after** rule selection, **before** feature
filtering. An override may **narrow** the chain but never widen it beyond the matched rule's targets.


| Field                                | Type                  | Role in the large picture                                                                                                                                                |
| ------------------------------------ | --------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `overrides[].installation_id`        | `string` (UUID)       | Which clinic this override applies to. Only the first matching entry is used (`.find()`).                                                                                |
| `overrides[].exclude_providers`      | `string[]`, optional  | Drop targets whose `provider_id` is listed. Recorded as `installation_excluded`. Omitted = no exclusions.                                                                |
| `overrides[].pin_target`             | object, optional      | Keep exactly one `{ provider_id, model_id }`; all other targets in the rule are `installation_excluded`. If the pin is not in the rule's chain, the chain becomes empty. |
| `overrides[].pin_target.provider_id` | `string`              | Required when `pin_target` is present.                                                                                                                                   |
| `overrides[].pin_target.model_id`    | `string`              | Required when `pin_target` is present.                                                                                                                                   |
| `overrides[].force_cost_class`       | `CostClass`, optional | Third input to effective cost-class minimum (with manifest ceiling and entitlement cap). Recorded as `cost_class_source: installation_override` when it binds.           |


**Cost class — three names, three roles**

`cost_class` appears in three places; only two participate in routing:


| Where                           | Used?   | Role                                                                                                                         |
| ------------------------------- | ------- | ---------------------------------------------------------------------------------------------------------------------------- |
| `defaults.cost_class`           | **No**  | Schema placeholder; see [§4.5](#45-hardcoded-ignored-and-wiring-gaps)                                                        |
| `rules[].match.cost_classes`    | **Yes** | Rule filter on effective cost class                                                                                          |
| `targets[].features.cost_class` | **Yes** | Per-model tier; a known class above the effective ceiling is `cost_class_excluded`; missing/unknown is `feature_unsupported` |


Effective cost class = **minimum** of manifest ceiling, entitlement cap, and optional
`force_cost_class`. Client never sends cost class ([§3.4](#34-field-by-field-reference-every-group) three seams).

**Worked example:** manifest `standard`, entitlement `premium`, no override → effective =
`standard`. Targets tagged `economy` or `standard` stay; `premium` targets get
`cost_class_excluded`. Override `force_cost_class: "economy"` → only economy targets remain.

### 4.5 Hardcoded, ignored, and wiring gaps

Fields and behaviours that exist in the schema or architecture but are not fully wired today.
**Action needed** marks gaps that should be closed for production fidelity.


| Item                                                               | Status                              | Why                                                                                                                                                                                                                                                                                                                                                                                                                                                                        | Action needed                                                                           |
| ------------------------------------------------------------------ | ----------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| `defaults.cost_class`                                              | **Ignored at runtime**              | Retained for [§4.3.7](../01-ai-platform.md#437-provider-router-and-policy-engine) document-shape parity; `resolveEffectiveCostClass` reads only the three-source minimum                                                                                                                                                                                                                                                                                                   | None — intentional. Do not rely on this field for routing.                              |
| `defaults.max_parallel_attempts` / `rules[].max_parallel_attempts` | **Ignored at runtime**              | Parallel racing is not implemented; `runInvocation` walks `chain[]` sequentially. The field is not on `RoutingDecision` and is not persisted                                                                                                                                                                                                                                                                                                                               | None — intentional. Do not rely on this field.                                          |
| `manifestCostClass` in `worker.ts`                                 | **Hardcoded** `"standard"`          | Manifest Routing group has a cost-class field in architecture ([§4.3.7](../01-ai-platform.md#437-provider-router-and-policy-engine)) but invoke path does not load it yet                                                                                                                                                                                                                                                                                                  | **Yes** — wire from `manifest.Routing` cost class                                       |
| `entitlementMaxCostClass` in `worker.ts`                           | **Hardcoded** `"premium"`           | Entitlement `max_cost_class` is architectural ([§4.3.7](../01-ai-platform.md#437-provider-router-and-policy-engine)) but not a D1 column today                                                                                                                                                                                                                                                                                                                             | **Yes** — load from entitlement row when column exists                                  |
| `routingTier` in `worker.ts`                                       | **From admission**                  | `runFreshEventSource` passes `routingTierFromAdmission(...)` (soft threshold `degraded: true`, or grace) into `selectCandidateChain` — same value the guard journals as `ai_request.routing_tier`                                                                                                                                                                                                                                                                          | None — closed                                                                           |
| `routing_decision.required_features`                               | **Request requirements only**       | `selectCandidateChain` sets this to `context.requirements`, not the merged rule floor — filtering uses merged floor but journal shows manifest-only                                                                                                                                                                                                                                                                                                                        | Optional — journal accuracy improvement                                                 |
| Latency mismatch `reason_code`                                     | **Mapped to** `feature_unsupported` | Frozen enum has no `latency_unsupported` code (`router/index.ts` `filterTargets`)                                                                                                                                                                                                                                                                                                                                                                                          | None unless contract is extended                                                        |
| Malformed target feature fields                                    | **Fail closed at** `filterTargets`  | Missing/unknown `min_context_window`, `cost_class`, or `languages` → `feature_unsupported`; languages is `Array.isArray`-guarded so a missing array does not throw                                                                                                                                                                                                                                                                                                         | None — request-path defense; publish-time target-shape check remains the in-depth layer |
| Publish-time validation                                            | **Identity shape + warnings**       | `handleRoutingPolicyPublish` rejects a document whose `policy_id` / `policy_version` are missing or malformed (400 `invalid_policy_identity`); warns (200 `warnings`) with `unreferenced_policy` when no published capability references the policy id, or `latency_class_mismatch` when no target `latency_class` matches a referencing capability (matched by policy id only). Catch-all and target shape are still not checked.                                                                                                     | **Partial** — catch-all and target shape still unvalidated                              |
| `policy_id` / `policy_version` at publish                          | **Document is the source of truth** | The publish URL carries no identity; R2 key, D1 PK, and audit target are derived from `document.policy_id` / `document.policy_version`. There is no URL/document mismatch to reject — `policy_identity_mismatch` exists only as the runtime router check against the D1 row.                                                                                                                                                        | None — closed                                                                           |
| Extra JSON keys                                                    | **Stored, ignored**                 | R2 body is written as-is; router reads only known fields                                                                                                                                                                                                                                                                                                                                                                                                                   | None — but avoid relying on unknown keys                                                |
| `rule_id` uniqueness                                               | **Not enforced**                    | Duplicate ids make journal attribution ambiguous                                                                                                                                                                                                                                                                                                                                                                                                                           | Ops discipline — consider publish-time check                                            |
| Kill switches                                                      | **Not in R2 document**              | Live in D1 (`kill_switch`); operators arm/disarm via `POST /control/kill-switches/arm` and `POST /control/kill-switches/disarm` (JSON body `{"scope":"…","target":"…"}`). Guard stage 5 collects active `provider:<id>` rows as `killedProviderIds` and the router applies them in `filterTargets`. Capability-level kills (manifest flag, D1 `global` / `capability:` / `installation:`) 503 before routing. Invoke-path routing shares the isolate `ConfigCache`, so `collectKilledProviderIds` `consult` can hit kill-switch entries the guard already loaded (still merged with `RouterContext.killedProviderIds`) | None — isolate cache is a copy of D1, not a second source of truth                      |




## 5. D1 `routing_policy` row — every column


| Column                    | Example                                          | Meaning                                                                                                                                                                                                      |
| ------------------------- | ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `policy_id`               | `standard`                                       | PK part                                                                                                                                                                                                      |
| `version`                 | `1`                                              | PK part (TEXT). Latest-version reads do **not** `ORDER BY version` — TEXT sorts `"10"` before `"9"`. Control (canary/promote/rollback) and config-cache serving use `ORDER BY active_from DESC, rowid DESC`. |
| `content_pointer`         | `control/routing-policy/standard/1.json`         | R2 key                                                                                                                                                                                                       |
| `active_from`             | ISO timestamp                                    | When published/activated                                                                                                                                                                                     |
| `activated_by`            | `platform-operator`                              | `OPERATOR_ID`                                                                                                                                                                                                |
| `canary_installation_ids` | `NULL` or JSON array                             | Installations on canary version                                                                                                                                                                              |
| `status`                  | `published` / `canary` / `active` / `superseded` | Lifecycle                                                                                                                                                                                                    |




## 6. Control endpoints

Malformed control paths fall through to HTTP 404 plain-text `Not Found` at the worker router — not `400 invalid_route` (dispatch pre-filters with handler-identical regexes; the handler's `invalid_route` branch is a direct-invocation seam only).


### 6.0 Greenfield bootstrap

Script: `ai-platform/scripts/bootstrap-routing-policy.sh` (npm: `bootstrap:routing-policy`).

**When:** after D1 migrations and with the Worker reachable (`npm run dev` locally, or a deployed gateway URL).

**What it does:**

1. Reads `control/routing-policy/platform-default/1.json` (`policy_id: "standard"`, `policy_version: 1`).
2. `POST /control/routing-policies/publish` if that version is not yet in D1 (409 `already_published` is treated as success).
3. `POST /control/routing-policies/standard/versions/1/promote` so config-cache serving finds `status='active'`.

**Idempotent:** exits cleanly when `standard@1` is already active; skips when another version is already active for `standard`.

**Operator token:** `OPERATOR_BEARER_TOKEN` env var, or `ai-platform/.dev.vars` / `.dev.vars.development`.

```bash
cd ai-platform
npx wrangler d1 migrations apply ai-platform-development --local --env development
npm run dev   # separate terminal
npm run bootstrap:routing-policy
```

Deployed env (remote D1 + Worker URL):

```bash
npm run bootstrap:routing-policy -- --env staging --remote --gateway https://…
```

Publish alone leaves `status=published`, which invoke does **not** serve ([§9.3.7](#937-published-policy-is-not-served)). The bootstrap script exists so operators do not have to remember the promote step on every fresh platform.


### 6.1 Publish: `POST /control/routing-policies/publish`

**Body:**

```json
{ "document": { /* RoutingPolicyDocument */ } }
```

The document is the **only source of identity**. There is no `{policyId}` / `{version}` in the URL — the R2 key `control/routing-policy/{policy_id}/{version}.json`, the D1 primary key, and the `control_audit.target` (`{policy_id}@{version}`) are all derived from `document.policy_id` / `document.policy_version`. Canary/promote/rollback keep their versioned URLs because they address an already-published row and carry no document.

**Writes:** SELECT existing `(policy_id, version)` first. On a hit, return 409 `already_published` without touching R2 (a duplicate body must not overwrite the published object). Otherwise R2.put, then D1 INSERT `status=published`. The D1 insert + `control_audit` share one `DB.batch`; a UNIQUE/SQLITE_CONSTRAINT race (two concurrent first publishes) is still mapped to 409.

**Validation (before R2/D1 write) and D1 constraint mapping:**


| Result | Body                                          | Trigger                                                                                                                                                                                                                    |
| ------ | --------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 400    | `{ "error": "invalid_json" }`                 | Body does not parse as JSON                                                                                                                                                                                                |
| 400    | `{ "error": "missing_document" }`             | `document` key absent or not an object                                                                                                                                                                                     |
| 400    | `{ "error": "invalid_policy_identity" }`      | `document.policy_id` is not a non-empty string, or `document.policy_version` is not an integer ≥ 1 (a JSON **number** — string `"1"` is rejected). Fail closed: identity must be well-formed before any key is derived from it |
| 409    | `{ "error": "already_published" }`            | Same `(policy_id, version)` already exists in D1 (`PRIMARY KEY`); checked before R2.put so a rejected duplicate does not mutate the published object. Concurrent insert races still map UNIQUE/SQLITE_CONSTRAINT to 409. Other D1 errors → 500 `storage_error`. |
| 200    | `{ "warnings": ["latency_class_mismatch"] }`  | A published capability references this `policy_id` via `routingPolicyRef` (matched by id only), but no target `latency_class` equals that capability's `Routing.latencyClass`                                                       |
| 200    | `{ "warnings": ["unreferenced_policy"] }`     | No published capability manifest references this `policy_id` — the typical symptom of a typo'd id, which would otherwise publish silently                                                     |
| 200    | `{}`                                          | Identity is well-formed, a published manifest references this policy id, and latency is aligned                                                                                                                       |


`policy_identity_mismatch` is no longer a publish-time outcome — there is nothing to mismatch against. It survives only as the **runtime** check ([§8](#8-routing-failure-paths-post-accept)): the router re-validates document identity against the D1 row on every load, which catches out-of-band R2 overwrites ([§9.3.14](#9314-router-identity-schema-and-catch-all)).


Catch-all / target shape are still not validated at publish — see [§4.5](#45-hardcoded-ignored-and-wiring-gaps).

### 6.2 Canary: `POST …/canary`

**Body:**

```json
{
  "installation_ids": ["<uuid>"],
  "cohort_name": "optional label"
}
```

`installation_ids` is required (non-empty array). When present, `cohort_name` is persisted in audit `after_pointer` JSON under `details.cohort_name` (not a D1 column).

**Multi-canary coexistence:** Multiple rows of the same `policy_id` may be `status='canary'` at once — the handler updates only the addressed `(policy_id, version)` row.

**Cross-version `before_pointer`:** `priorCanary` reads the latest canary row for the **policy** (`ORDER BY active_from DESC, rowid DESC`), so a v2 canary audit `before_pointer` may name v1's cohort list.

**Serving order:** For installation-scoped cache keys, the reader scans canary rows `ORDER BY active_from DESC, rowid DESC` and serves the first whose `canary_installation_ids` contains the installation; otherwise falls through to the active row (`config-cache/index.ts`).

**Canary R2 miss — no fallback:** When a matching canary row's R2 object is missing, `loadRoutingPolicyDocument` returns `"miss"` from the canary branch without consulting the active row.

**Writes:** D1 UPDATE `status=canary`, `canary_installation_ids`.


| HTTP | `error`                     | Trigger                                              |
| ---- | --------------------------- | ---------------------------------------------------- |
| 401  | `unauthorized`              | Missing / wrong operator bearer                      |
| 400  | `invalid_json`              | Body does not parse as JSON                          |
| 400  | `missing_installation_ids`  | Field absent, not an array, or empty array           |
| 404  | `policy_version_not_found`  | Addressed row missing                                |
| 404  | `installation_not_found`    | Any listed id missing from `installation`            |
| 409  | `illegal_policy_transition` | Source status neither `published` nor `canary`       |
| 500  | `storage_error`             | D1 batch failure via `runControlBatch`               |




### 6.3 Promote: `POST …/promote`

**Request body:** ignored entirely — no `parseJsonBody`.

**Writes:** Supersede other active/canary; target → `active`. The prior-active row used for `control_audit.before_pointer` is selected with `ORDER BY active_from DESC, rowid DESC` (not TEXT `version`) so a same-second `active_from` tie picks the later-inserted row — lexical `"9" > "10"` would otherwise win.

**Promote** rejects `active` and `superseded` source rows with `409 illegal_policy_transition`.


| HTTP | `error`                     | Trigger                                              |
| ---- | --------------------------- | ---------------------------------------------------- |
| 401  | `unauthorized`              | Missing / wrong operator bearer                      |
| 404  | `policy_version_not_found`  | Addressed row missing                                |
| 409  | `illegal_policy_transition` | Source row is `active` or `superseded`               |
| 500  | `storage_error`             | D1 batch failure via `runControlBatch`               |

### 6.4 Rollback: `POST …/rollback`

**Request body:** ignored entirely — no `parseJsonBody`.

Reverts canary → published or active → previous superseded. Prior active / prior superseded lookup uses the same `ORDER BY active_from DESC, rowid DESC` tie-break as promote (and as config-cache serving reads), so rollback of an active version resurrects the true latest superseded row when several share an `active_from` timestamp.

**Rollback** of `published` or `superseded` rows returns `409 illegal_policy_transition`. Rollback of an `active` row with no superseded prior also returns `409 illegal_policy_transition`.


| HTTP | `error`                     | Trigger                                              |
| ---- | --------------------------- | ---------------------------------------------------- |
| 401  | `unauthorized`              | Missing / wrong operator bearer                      |
| 404  | `policy_version_not_found`  | Addressed row missing                                |
| 409  | `illegal_policy_transition` | Source row is `published` or `superseded`; or active rollback with no superseded prior |
| 500  | `storage_error`             | D1 batch failure via `runControlBatch`               |

## 7. Router output (`RoutingDecision`) — every field

Produced by `selectCandidateChain` after invoke preload. See [§4.5](#45-hardcoded-ignored-and-wiring-gaps) for
fields that are partially hardcoded in `worker.ts` today.


| Field                  | Meaning                                                                                                                                                          |
| ---------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `policy_id`            | From document                                                                                                                                                    |
| `policy_version`       | From document                                                                                                                                                    |
| `rule_id`              | Matched rule                                                                                                                                                     |
| `effective_cost_class` | Min of manifest, entitlement cap, override                                                                                                                       |
| `cost_class_source`    | Which input bound the cost (`manifest` / `entitlement_cap` / `installation_override`)                                                                            |
| `routing_tier`         | `standard` or `degraded` — from request context (`match.tiers` filter); invoke path uses `routingTierFromAdmission` so this matches D1 `ai_request.routing_tier` |
| `required_features`    | Manifest requirements only (not the merged rule floor used for filtering)                                                                                        |
| `chain[]`              | `{ ordinal, provider_id, model_id, max_attempts, timeout_ms }`                                                                                                   |
| `excluded[]`           | `{ provider_id, model_id, reason_code }`                                                                                                                         |


`max_parallel_attempts` is **not** a `RoutingDecision` field. After `selectCandidateChain`, Stage 10 writes this object as JSON onto the existing D1 row (`ai_request.routing_decision`) via `persistRoutingDecision` — one UPDATE, no new tables. Override provenance is visible through `cost_class_source` (`installation_override` when `force_cost_class` binds) and `excluded[].reason_code` (`installation_excluded` for `exclude_providers` / `pin_target`). That JSON is how support answers "why did this request go to model X?" from the ledger.

**Target exclusion** `reason_code` **values:** `kill_switch`, `feature_unsupported`, `context_window_too_small`, `language_unsupported`, `installation_excluded`, `cost_class_excluded`.

## 8. Routing failure paths (post-accept)

Routing errors thrown post-accept (`ConfigCacheMissError`, any `RoutingPolicyError`) are caught by the `runFreshEventSource` `.catch` and surface on the wire **only** as SSE `failed` with `data.code = "internal_error"` — router internal codes (`policy_identity_mismatch`, `no_matching_rule`, etc.) **never** reach the client. The catch also settles the request as `Failed` / `internal_error` via `settlePostAcceptInternalError` (journal + `recordTerminalState` + synthetic `ai_attempt`).


| Condition                     | Terminal SSE         | Persisted `ai_request` state | Notes |
| ----------------------------- | -------------------- | ---------------------------- | ----- |
| No active/canary policy in D1 | `failed`             | `Failed` / `internal_error`  | `routing_decision` NULL — miss before `persistRoutingDecision` |
| R2 document missing (active or canary branch) | `failed` | `Failed` / `internal_error` | Canary R2 miss does **not** fall back to the active row |
| Policy id/version mismatch    | `failed`             | `Failed` / `internal_error`  | Router throws `RoutingPolicyError` `policy_identity_mismatch`; client sees only `internal_error` |
| No matching rule              | `failed`             | `Failed` / `internal_error`  | Unreachable on production path once catch-all validates — see [§9.3.21](#9321-unreachable-and-operator-hostile-paths) |
| All targets excluded          | `failed`             | `Failed` / `provider_unavailable` | `routing_decision` persisted with empty `chain` |


Malformed `targets[].features` (missing/unknown `min_context_window`, `cost_class`, or `languages`) exclude that target with `feature_unsupported` rather than routing it or throwing. If that empties the chain, the terminal is `provider_unavailable` — not `internal_error`.

---



## 9. Behavioral verification

Live probes against a local Worker (`npm run dev`) plus D1/R2 inspection. Each probe is an operator action and the outcome you should see — not a unit test. Run **[§9.3](#93-ordered-probes) top to bottom** on a throwaway local platform. If every probe matches, this stage is working.

Control routes are operator-only (`requireOperator` → Bearer `OPERATOR_BEARER_TOKEN`). The router runs only after Stages 8–9 accept a request; missing policy then is an SSE `failed` on the already-accepted stream, not an HTTP JSON reject. After any D1/R2 mutation that invoke should see, wait **31 s** (or restart `npm run dev`) so `isolateConfigCache`’s 30 s TTL expires.

### 9.1 Setup

- Local Worker from `ai-platform/` (`npm run dev` → `http://127.0.0.1:8787`) with `OPERATOR_BEARER_TOKEN` and `OPERATOR_ID=platform-operator` ([Stage 0](02-stage-0-platform-configuration-and-boot.md)). Prefer a D1/R2 you can wipe; several probes delete `routing_policy` rows and overwrite R2 keys.
- One enrolled installation **I0** ([Stage 3](05-stage-3-platform-installation-enrollment.md)) whose entitlement is **active** for `clinic.visit_summary@1.0.0` ([Stage 4](06-stage-4-entitlement-and-capability-grants.md) — without this, probes from [§9.3.7](#937-published-policy-is-not-served) never reach routing). Save `org` / `branch` claims from a staff AAT ([Stage 6](08-stage-6-minting-an-aat.md)).
- A second enrolled installation **I1** (or any other `installation.installation_id`) for canary split and `installation_not_found` contrast.
- `jq` (or Python) to pretty-print JSON. D1/R2 commands below use `--local --env development`.

```bash
cd ai-platform
export GATEWAY='http://127.0.0.1:8787'
export OPERATOR_BEARER_TOKEN='…'
export INSTALLATION_ID='<I0>'
export OTHER_INSTALLATION_ID='<I1>'
export AAT='<staff AAT JWS>'
export ORG_ID='<AAT org claim>'
export BRANCH_ID='<AAT branch claim>'

d1() {
  npx wrangler d1 execute ai-platform-development --local --env development --command "$1"
}

r2get() {
  npx wrangler r2 object get ai-platform-development "$1" \
    --file "$2" --local --env development
}

r2put() {
  npx wrangler r2 object put ai-platform-development "$1" \
    --file "$2" --local --env development
}

r2del() {
  npx wrangler r2 object delete ai-platform-development "$1" \
    --local --env development
}

publish() {
  local file="$1"
  curl -sS -D - -o /tmp/rp-http-body.json \
    -X POST "$GATEWAY/control/routing-policies/publish" \
    -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary @"$file"
  echo
  cat /tmp/rp-http-body.json; echo
}

invoke() {
  local key="${1:-rp-$(date +%s%N)}"
  curl -sN -X POST "$GATEWAY/v1/requests" \
    -H "Authorization: Bearer $AAT" \
    -H "Content-Type: application/json" \
    -H "x-idempotency-key: $key" \
    -H "x-capability-version: 1.0.0" \
    -d "{
      \"capability_id\": \"clinic.visit_summary\",
      \"user_intent\": \"Summarize today's visit for the chart.\",
      \"context\": {
        \"org\": \"$ORG_ID\",
        \"branch\": \"$BRANCH_ID\",
        \"visit.chief_complaint@v1\": \"Patient reports headache for 3 days.\",
        \"routing_tier\": \"degraded\",
        \"degraded\": true,
        \"degraded_notice\": true
      }
    }"
}
```

Inspect the latest journal row after an invoke:

```bash
d1 "SELECT request_id, state, routing_tier, terminal_error_code, routing_decision
    FROM ai_request ORDER BY created_at DESC LIMIT 1"
```

SSE frames look like `event: accepted` then later `event: failed` / `event: completed` with `data: { "code": "…", … }`.

### 9.2 Coverage

Every happy and failure claim in this file maps to a probe. Carry them all out.


| Claim                                                                                                             | Probe                                                                                                                                                                                     |
| ----------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Manifest is bundled Worker JSON, not stored in D1 or R2                                                           | [§9.3.12](#9312-manifest-link-and-independent-switches)                                                                                                                                   |
| `Identity.capabilityId` feeds `match.capability_ids`                                                              | [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                                                                     |
| `Identity` `version` / `title` / `lifecycleState` / `successorId` are not routing                                 | [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                                                                              |
| `Access.*` is not routing (entitlement / capability resolve / guard)                                              | [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                                                                              |
| `Interaction.*` is not routing                                                                                    | [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                                                                              |
| `Input.*` is not routing (including `allowedLanguages` ≠ routing language)                                        | [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                                                                              |
| `Context requirements` is not routing; no `freshnessHint` in the live specimen                                    | [§9.3.12](#9312-manifest-link-and-independent-switches)                                                                                                                                   |
| `Prompt binding.*` is not routing                                                                                 | [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                                                                              |
| `Output.mode` (not `requiredProviderFeatures.structuredOutput`) sets `structured_output_required`                 | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                        |
| `Output` `outputSchemaRef` / `businessValidationRuleRefs` / `repairPolicy` are not routing                        | [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                                                                              |
| `Routing.routingPolicyRef` format `routing/{id}` names playbook id only (e.g. `standard`)                              | [§9.3.12](#9312-manifest-link-and-independent-switches), [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                             |
| D1 status (active/canary), not any legacy `@vN` suffix in the ref, picks which version is served                                    | [§9.3.9](#939-canary-success-and-serving-split), [§9.3.10](#9310-promote-to-active)                                                                                                       |
| `Routing.requiredProviderFeatures.contextWindow` → `min_context_window` floor                                     | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                               |
| `Routing.requiredProviderFeatures.language` → `requirements.languages`                                            | [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                                                                      |
| `Routing.latencyClass` → `match.latency_classes` and target `features.latency_class`                              | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.18](#9318-target-exclusions-and-empty-chain)                                                                                  |
| `Routing.degradedTierPolicy` is schema-only today                                                                 | [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                                                                              |
| `Economics.*` is not live routing; `manifestCostClass` is hardcoded `"standard"`                                  | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                        |
| `Governance.*` is not routing                                                                                     | [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                                                                              |
| Merge: `structured_output_required` is OR of `Output.mode` and rule `requires`                                    | [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                                                                     |
| Merge: `min_context_window` is `Math.max`                                                                         | [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                                                                     |
| Merge: languages are a union (rule can add, not remove)                                                           | [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                                                                     |
| Merge: `latency_class` stays manifest-only                                                                        | [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                                                                      |
| `routingTier` comes from admission (`routingTierFromAdmission`), matches `ai_request.routing_tier`                | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                               |
| Client `routing_tier` / `degraded` / `degraded_notice` body keys are ignored                                      | [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                                                                      |
| R2 key is `control/routing-policy/{policy_id}/{version}.json`                                                     | [§9.3.4](#934-first-publish-and-storage-inspection)                                                                                                                                       |
| Publish derives that key from `document.policy_id` / `document.policy_version`, not the repo path `platform-default/` | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.6](#936-latency-warning-and-unreferenced-policy)                                                                               |
| Router does not read R2 on the hot path (config cache `row.document`)                                             | [§9.3.13](#9313-missing-r2-document)                                                                                                                                                      |
| `schema_version` always present; only `1` accepted                                                                | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.14](#9314-router-identity-schema-and-catch-all)                                                                                |
| `policy_id` / `policy_version` always present; must match D1 row                                                  | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.14](#9314-router-identity-schema-and-catch-all)                                                                                |
| `defaults` always present; `defaults.cost_class` schema-retained / ignored                                        | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                 |
| `defaults.max_parallel_attempts` schema-retained / ignored                                                        | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                 |
| `rules` always present (non-empty); last rule must be catch-all                                                   | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.14](#9314-router-identity-schema-and-catch-all)                                                                                |
| `rules[].rule_id` copied onto `routing_decision.rule_id`; uniqueness not enforced                                 | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.21](#9321-unreachable-and-operator-hostile-paths)                                                                             |
| `rules[].match` may be `{}` (wildcard)                                                                            | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                 |
| `match.capability_ids` optional; non-empty is an allow-list                                                       | [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                                                                     |
| `match.installation_ids` optional; non-empty is an allow-list                                                     | [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                                                                     |
| `match.cost_classes` optional; filters on **effective** cost class                                                | [§9.3.17](#9317-overrides-and-cost-class)                                                                                                                                                 |
| `match.tiers` optional; `degraded` is server-side only                                                            | [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                                                                     |
| `match.languages` optional; subset check (`matchAllLanguages`)                                                    | [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                                                                     |
| `match.latency_classes` optional; compared to manifest latency                                                    | [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                                                                     |
| `requires.structured_output` always present; OR-merged                                                            | [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                                                                     |
| `requires.min_context_window` always present; `0` adds no extra floor                                             | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                               |
| `requires.languages` always present; `[]` adds none                                                               | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                               |
| `targets[].provider_id` / `model_id` always present; model is pinned                                              | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                 |
| `targets[].features.structured_output` always present                                                             | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                |
| `targets[].features.min_context_window` missing/non-numeric → `feature_unsupported`                               | [§9.3.18](#9318-target-exclusions-and-empty-chain)                                                                                                                                        |
| Declared window too small → `context_window_too_small`                                                            | [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                                                                                     |
| `targets[].features.languages` missing/non-array → `feature_unsupported`                                          | [§9.3.18](#9318-target-exclusions-and-empty-chain)                                                                                                                                        |
| Declared languages missing a required one → `language_unsupported`                                                | [§9.3.18](#9318-target-exclusions-and-empty-chain)                                                                                                                                        |
| `features.latency_class` mismatch/missing → `feature_unsupported` (no `latency_unsupported`)                      | [§9.3.18](#9318-target-exclusions-and-empty-chain)                                                                                                                                        |
| Missing/unknown `features.cost_class` → `feature_unsupported`                                                     | [§9.3.18](#9318-target-exclusions-and-empty-chain)                                                                                                                                        |
| Known `cost_class` above effective ceiling → `cost_class_excluded`                                                | [§9.3.17](#9317-overrides-and-cost-class)                                                                                                                                                 |
| `targets[].max_attempts` / `timeout_ms` copied onto `chain[]`                                                     | [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                                                                      |
| `rules[].max_parallel_attempts` schema-retained; not on `RoutingDecision`                                         | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                 |
| `overrides` always present (may be `[]`)                                                                          | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.6](#936-latency-warning-and-unreferenced-policy)                                                                               |
| First matching `overrides[].installation_id` wins (`.find()`)                                                     | [§9.3.17](#9317-overrides-and-cost-class)                                                                                                                                                 |
| `exclude_providers` → `installation_excluded`                                                                     | [§9.3.17](#9317-overrides-and-cost-class)                                                                                                                                                 |
| `pin_target` keeps one pair; pin absent from the rule → empty chain                                               | [§9.3.17](#9317-overrides-and-cost-class)                                                                                                                                                 |
| `force_cost_class` binds as `cost_class_source: installation_override`                                            | [§9.3.17](#9317-overrides-and-cost-class)                                                                                                                                                 |
| Override may narrow, never widen beyond the matched rule                                                          | [§9.3.17](#9317-overrides-and-cost-class)                                                                                                                                                 |
| Effective cost class = min of hardcoded manifest `"standard"`, entitlement cap `"premium"`, optional override     | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.17](#9317-overrides-and-cost-class)                                                                                           |
| Extra JSON keys are stored and ignored                                                                            | [§9.3.4](#934-first-publish-and-storage-inspection)                                                                                                                                       |
| Sibling price table is not this R2 document                                                                       | [§9.3.12](#9312-manifest-link-and-independent-switches)                                                                                                                                   |
| Checked-in fixture identity is `policy_id: "standard"` / `policy_version: 1`                                      | [§9.3.6](#936-latency-warning-and-unreferenced-policy)                                                                                                                                    |
| D1 `policy_id` + `version` are the PK; `version` is TEXT                                                          | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.11](#9311-rollback-and-version-tie-break)                                                                                      |
| Latest-version reads do **not** `ORDER BY version` (TEXT would sort `"10"` before `"9"`)                          | [§9.3.11](#9311-rollback-and-version-tie-break)                                                                                                                                           |
| Control + config-cache serving use `ORDER BY active_from DESC, rowid DESC`                                        | [§9.3.10](#9310-promote-to-active), [§9.3.11](#9311-rollback-and-version-tie-break)                                                                                                       |
| D1 `content_pointer` equals the R2 key                                                                            | [§9.3.4](#934-first-publish-and-storage-inspection)                                                                                                                                       |
| D1 `active_from` is an ISO timestamp written at publish/activate                                                  | [§9.3.4](#934-first-publish-and-storage-inspection)                                                                                                                                       |
| D1 `activated_by` is `OPERATOR_ID` (`platform-operator`)                                                          | [§9.3.4](#934-first-publish-and-storage-inspection)                                                                                                                                       |
| D1 `canary_installation_ids` is `NULL` or a JSON array                                                            | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.9](#939-canary-success-and-serving-split)                                                                                      |
| D1 `status` is `published` / `canary` / `active` / `superseded`                                                   | [§9.3.4](#934-first-publish-and-storage-inspection), [§9.3.9](#939-canary-success-and-serving-split), [§9.3.10](#9310-promote-to-active), [§9.3.11](#9311-rollback-and-version-tie-break) |
| There is no GET control endpoint for routing policies                                                             | [§9.3.2](#932-who-may-call-control-apis)                                                                                                                                                  |
| Operator Bearer may call publish/canary/promote/rollback                                                          | [§9.3.2](#932-who-may-call-control-apis)                                                                                                                                                  |
| Missing/wrong Bearer, or a staff AAT, → 401 `unauthorized`                                                        | [§9.3.2](#932-who-may-call-control-apis)                                                                                                                                                  |
| Publish body is `{ "document": { … } }`; missing document → 400 `missing_document`                                | [§9.3.3](#933-publish-failure-paths)                                                                                                                                                      |
| Invalid JSON body → 400 `invalid_json`                                                                            | [§9.3.3](#933-publish-failure-paths)                                                                                                                                                      |
| Publish URL carries no identity; document is the only source of `policy_id` / `policy_version`                    | [§9.3.3](#933-publish-failure-paths), [§9.3.4](#934-first-publish-and-storage-inspection)                                                                                                 |
| Missing/malformed document identity → 400 `invalid_policy_identity`; no R2.put / no D1 insert                     | [§9.3.3](#933-publish-failure-paths)                                                                                                                                                      |
| Publish of a policy id no capability references → 200 `{ "warnings": ["unreferenced_policy"] }`                   | [§9.3.4](#934-first-publish-and-storage-inspection)                                                                                                                                       |
| First publish: D1 existence check, then R2.put, then D1 INSERT `status=published`                                 | [§9.3.4](#934-first-publish-and-storage-inspection)                                                                                                                                       |
| First publish 200 `{}` when a capability references this version and latency is aligned                           | [§9.3.6](#936-latency-warning-and-unreferenced-policy)                                                                                                                                    |
| First publish 200 `{ "warnings": ["latency_class_mismatch"] }` when no target latency matches visit-summary       | [§9.3.6](#936-latency-warning-and-unreferenced-policy)                                                                                                                                    |
| Duplicate `(policy_id, version)` → 409 `already_published` without touching R2                                    | [§9.3.5](#935-duplicate-publish-leaves-r2-unchanged)                                                                                                                                      |
| Concurrent UNIQUE/SQLITE_CONSTRAINT also maps to 409                                                              | [§9.3.21](#9321-unreachable-and-operator-hostile-paths)                                                                                                                                   |
| Other D1 errors → 500 `storage_error`                                                                             | [§9.3.21](#9321-unreachable-and-operator-hostile-paths)                                                                                                                                   |
| Canary/promote/rollback D1 batch failure → 500 `storage_error` via `runControlBatch`                              | [§6.2](#62-canary-post-canary), [§6.3](#63-promote-post-promote), [§6.4](#64-rollback-post-rollback)                                                                                                                                   |
| Publish does not validate catch-all or target shape                                                               | [§9.3.14](#9314-router-identity-schema-and-catch-all), [§9.3.18](#9318-target-exclusions-and-empty-chain)                                                                                 |
| Canary body `installation_ids` absent/non-array/empty → 400 `missing_installation_ids`                                             | [§9.3.8](#938-canary-failure-paths)                                                                                                                                                       |
| Canary malformed JSON → 400 `invalid_json`                                                                                        | [§9.3.8](#938-canary-failure-paths)                                                                                                                                                       |
| Canary id not in `installation` → 404 `installation_not_found`                                                    | [§9.3.8](#938-canary-failure-paths)                                                                                                                                                       |
| Canary/promote/rollback on unknown version → 404 `policy_version_not_found`                                       | [§9.3.8](#938-canary-failure-paths)                                                                                                                                                       |
| Canary on illegal source status → 409 `illegal_policy_transition`                                                        | [§9.3.8](#938-canary-failure-paths), [§9.3.10](#9310-promote-to-active)                                                                                                                                                        |
| Multi-canary coexistence; cross-version audit `before_pointer`; serving `active_from DESC, rowid DESC`              | [§6.2](#62-canary-post-canary), [§9.3.9](#939-canary-success-and-serving-split)                                                                                                                                           |
| Canary R2 miss does not fall back to active row                                                                     | [§6.2](#62-canary-post-canary), [§8](#8-routing-failure-paths-post-accept)                                                                                                                                           |
| Canary success: `status=canary`, `canary_installation_ids` written; `cohort_name` in audit `after_pointer.details`              | [§9.3.9](#939-canary-success-and-serving-split)                                                                                                                                           |
| Canary cohort is served that document; others keep the active version                                             | [§9.3.9](#939-canary-success-and-serving-split)                                                                                                                                           |
| Promote body ignored; rejects `active`/`superseded` with 409; supersedes other active/canary; target → `active`                                           | [§6.3](#63-promote-post-promote), [§9.3.10](#9310-promote-to-active)                                                                                                                                                        |
| Promote `control_audit.before_pointer` uses `ORDER BY active_from DESC, rowid DESC`                               | [§9.3.11](#9311-rollback-and-version-tie-break)                                                                                                                                           |
| Rollback body ignored; canary → `published` (clears canary ids)                                                                 | [§6.4](#64-rollback-post-rollback), [§9.3.11](#9311-rollback-and-version-tie-break)                                                                                                                                           |
| Rollback active → prior superseded (same ORDER BY); `published`/`superseded` rollback → 409         | [§6.4](#64-rollback-post-rollback), [§9.3.11](#9311-rollback-and-version-tie-break)                                                                                                                                           |
| `RoutingDecision.policy_id` / `policy_version` from the served document                                           | [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                                                                      |
| `RoutingDecision.rule_id` is the matched rule                                                                     | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                               |
| `effective_cost_class` / `cost_class_source`                                                                      | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.17](#9317-overrides-and-cost-class)                                                                                           |
| `routing_tier` on the decision equals D1 `ai_request.routing_tier`                                                | [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                                                                      |
| `required_features` is manifest requirements only (not the merged floor)                                          | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.16](#9316-match-clauses-and-requirement-floors)                                                                               |
| `chain[]` is `{ ordinal, provider_id, model_id, max_attempts, timeout_ms }`                                       | [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                                                                      |
| `excluded[]` is `{ provider_id, model_id, reason_code }`                                                          | [§9.3.17](#9317-overrides-and-cost-class), [§9.3.18](#9318-target-exclusions-and-empty-chain), [§9.3.19](#9319-provider-kill-switch-failover)                                             |
| `max_parallel_attempts` is not a decision field and is not persisted                                              | [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                                                                      |
| Stage 10 persists the object onto the existing `ai_request` row (`persistRoutingDecision`)                        | [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                                                                      |
| Persist happens only after `selectCandidateChain` returns — throws leave `routing_decision` NULL                  | [§9.3.7](#937-published-policy-is-not-served), [§9.3.13](#9313-missing-r2-document), [§9.3.14](#9314-router-identity-schema-and-catch-all)                                                |
| No active/canary policy → SSE `failed` `internal_error`; request settles `Failed`                                                           | [§8](#8-routing-failure-paths-post-accept), [§9.3.7](#937-published-policy-is-not-served)                                                                                                                                             |
| R2 document missing → SSE `failed` `internal_error`; request settles `Failed`                                                               | [§8](#8-routing-failure-paths-post-accept), [§9.3.13](#9313-missing-r2-document)                                                                                                                                                      |
| Router internal codes never on the wire; client sees only `internal_error` for routing throws | [§8](#8-routing-failure-paths-post-accept)                                                                                                                                     |
| Policy id/version mismatch → worker logs `policy_identity_mismatch`; SSE wraps as `internal_error` | [§8](#8-routing-failure-paths-post-accept), [§9.3.14](#9314-router-identity-schema-and-catch-all)                                                                                                                                     |
| `unsupported_schema_version` / `missing_catch_all` same wrap                                                      | [§9.3.14](#9314-router-identity-schema-and-catch-all)                                                                                                                                     |
| `no_matching_rule` is unreachable once a catch-all last rule exists                                               | [§9.3.21](#9321-unreachable-and-operator-hostile-paths)                                                                                                                                   |
| All targets excluded → SSE `failed` `provider_unavailable` with a persisted decision                              | [§9.3.18](#9318-target-exclusions-and-empty-chain)                                                                                                                                        |
| Malformed target features fail closed (`feature_unsupported`); empty chain is not `internal_error`                | [§9.3.18](#9318-target-exclusions-and-empty-chain)                                                                                                                                        |
| `reason_code` `kill_switch` excludes that provider; remaining targets stay in order; no 503 of the capability     | [§9.3.19](#9319-provider-kill-switch-failover)                                                                                                                                            |
| Kill switches armed/disarmed via `POST /control/kill-switches/arm` and `…/disarm`; D1 table `kill_switch`                              | [§9.3.19](#9319-provider-kill-switch-failover)                                                                                              |
| Capability-level kills 503 before routing; kill switches are D1, not the R2 document                              | [§9.3.19](#9319-provider-kill-switch-failover), [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                              |
| This stage does not entitle, enroll, mint AATs, or call providers                                                 | [§9.3.12](#9312-manifest-link-and-independent-switches), [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                     |
| Publish/canary/promote/rollback leave `entitlement` unchanged                                                     | [§9.3.12](#9312-manifest-link-and-independent-switches)                                                                                                                                   |
| `entitlementMaxCostClass` hardcoded `"premium"` (not a D1 column today)                                           | [§9.3.15](#9315-routingdecision-on-a-routed-request), [§9.3.20](#9320-what-this-stage-does-not-do)                                                                                        |
| Invocation walks `chain[]` sequentially (no parallel racing)                                                      | [§9.3.15](#9315-routingdecision-on-a-routed-request)                                                                                                                                      |
| `missing_r2_binding` is not inducible on a configured Worker                                                      | [§9.3.21](#9321-unreachable-and-operator-hostile-paths)                                                                                                                                   |




### 9.3 Ordered probes



#### 9.3.1 Reset to a known policy state

**Do:** wipe routing-policy index rows and the R2 keys this file uses. Do **not** delete `installation` / `entitlement` / `token_contract`.

```bash
d1 "DELETE FROM routing_policy"
d1 "DELETE FROM control_audit WHERE action LIKE 'routing_policy_%'"
d1 "DELETE FROM kill_switch WHERE scope = 'provider'"

for key in \
  control/routing-policy/probe/1.json \
  control/routing-policy/standard/1.json \
  control/routing-policy/standard/2.json \
  control/routing-policy/standard/3.json \
  control/routing-policy/standard/9.json \
  control/routing-policy/standard/10.json \
  control/routing-policy/standard/11.json
do
  r2del "$key" || true
done
```

**Expect:** `SELECT COUNT(*) FROM routing_policy` is `0`. Later probes start from an empty playbook index. Entitlement for **I0** is still `active`.

#### 9.3.2 Who may call control APIs

There is no GET of a routing policy. Inspection is D1 + R2 ([§5](#5-d1-routing_policy-row-every-column), [§4.1](#41-r2-object-key)).

**Do:**

```bash
curl -sS -D - -o /tmp/rp-http-body.json -X GET \
  "$GATEWAY/control/routing-policies/standard/versions/1"
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/publish" \
  -H "Content-Type: application/json" \
  -d '{"document":{"policy_id":"standard","policy_version":1}}'
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/publish" \
  -H "Authorization: Bearer not-the-operator-token" \
  -H "Content-Type: application/json" \
  -d '{"document":{"policy_id":"standard","policy_version":1}}'
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/publish" \
  -H "Authorization: Bearer $AAT" \
  -H "Content-Type: application/json" \
  -d '{"document":{"policy_id":"standard","policy_version":1}}'
echo; cat /tmp/rp-http-body.json; echo
```

**Expect:** GET of the collection path is **404** (versioned pattern requires `…/canary|promote|rollback`; publish is the bare `/control/routing-policies/publish`). The three POSTs are **401** `{ "error": "unauthorized" }`. Clinic staff (AAT) are not operators. Repeat a canary/promote/rollback URL without a Bearer — same 401. `routing_policy` is still empty.

#### 9.3.3 Publish failure paths

**Do:** as operator, malformed bodies and malformed document identity (before any successful write):

```bash
curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d 'not-json'
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"document":null}'
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"document":{"policy_version":1,"schema_version":1,"defaults":{},"rules":[],"overrides":[]}}'
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"document":{"policy_id":"standard","policy_version":"1","schema_version":1,"defaults":{},"rules":[],"overrides":[]}}'
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/publish" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"document":{"policy_id":"","policy_version":0,"schema_version":1,"defaults":{},"rules":[],"overrides":[]}}'
echo; cat /tmp/rp-http-body.json; echo
```

**Expect:** `not-json` → **400** `{ "error": "invalid_json" }`. `{}` and `{"document":null}` → **400** `{ "error": "missing_document" }`. Missing `policy_id`, string `policy_version` `"1"` (must be a JSON number), and empty `policy_id` / `0` version → **400** `{ "error": "invalid_policy_identity" }`. Identity is derived from the document alone — there is no URL to agree or disagree with, so `policy_identity_mismatch` is not a publish outcome anymore.

**Do:**

```bash
d1 "SELECT COUNT(*) AS n FROM routing_policy"
r2get "control/routing-policy/standard/1.json" /tmp/rp-should-miss.json || true
```

**Expect:** still zero D1 rows. R2 get fails / empty — identity validation runs **before** R2.put.

#### 9.3.4 First publish and storage inspection

Use a policy id **no bundled capability references**, so the publish returns the `unreferenced_policy` warning ([§6.1](#61-publish-post-controlrouting-policiespublish)). The document below includes every router-understood key plus schema-retained defaults, an extra unknown key, and a catch-all.

**Do:**

```bash
cat > /tmp/rp-probe-v1.json <<'EOF'
{
  "document": {
    "schema_version": 1,
    "policy_id": "probe",
    "policy_version": 1,
    "defaults": { "cost_class": "premium", "max_parallel_attempts": 9 },
    "ops_note": "extra key must be stored and ignored",
    "rules": [
      {
        "rule_id": "visit-summary-standard",
        "match": {
          "capability_ids": ["clinic.visit_summary"],
          "installation_ids": [],
          "cost_classes": ["standard", "premium"],
          "tiers": ["standard", "degraded"],
          "languages": ["en"],
          "latency_classes": ["standard"]
        },
        "requires": {
          "structured_output": false,
          "min_context_window": 0,
          "languages": []
        },
        "targets": [
          {
            "provider_id": "deepseek",
            "model_id": "deepseek-v4-flash",
            "features": {
              "structured_output": true,
              "min_context_window": 128000,
              "languages": ["en"],
              "latency_class": "standard",
              "cost_class": "standard"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          }
        ],
        "max_parallel_attempts": 4
      },
      {
        "rule_id": "catch-all",
        "match": {},
        "requires": {
          "structured_output": false,
          "min_context_window": 0,
          "languages": []
        },
        "targets": [
          {
            "provider_id": "deepseek",
            "model_id": "deepseek-v4-flash",
            "features": {
              "structured_output": true,
              "min_context_window": 128000,
              "languages": ["en"],
              "latency_class": "standard",
              "cost_class": "standard"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          },
          {
            "provider_id": "gemini",
            "model_id": "gemini-3.5-flash",
            "features": {
              "structured_output": true,
              "min_context_window": 128000,
              "languages": ["en"],
              "latency_class": "standard",
              "cost_class": "standard"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          }
        ]
      }
    ],
    "overrides": []
  }
}
EOF

publish /tmp/rp-probe-v1.json
```

**Expect:** HTTP **200** and body `{ "warnings": ["unreferenced_policy"] }`. No published capability has `routingPolicyRef: "routing/probe"` — the publish succeeds (identity is well-formed) but the warning flags that nothing references this policy id, the typical symptom of a typo'd `policy_id`.

**Do:** inspect R2 (every written field) and D1 (every column):

```bash
r2get "control/routing-policy/probe/1.json" /tmp/rp-probe-stored.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/rp-probe-stored.json"))
assert d["schema_version"]==1
assert d["policy_id"]=="probe" and d["policy_version"]==1
assert d["defaults"]["cost_class"]=="premium"
assert d["defaults"]["max_parallel_attempts"]==9
assert d["ops_note"].startswith("extra key")
assert d["rules"][0]["rule_id"]=="visit-summary-standard"
assert d["rules"][0]["max_parallel_attempts"]==4
assert d["rules"][0]["targets"][0]["model_id"]=="deepseek-v4-flash"
assert d["rules"][-1]["rule_id"]=="catch-all" and d["rules"][-1]["match"]=={}
assert d["overrides"]==[]
print("r2 ok", list(d))
PY

d1 "SELECT policy_id, version, content_pointer, active_from, activated_by,
           canary_installation_ids, status
    FROM routing_policy WHERE policy_id = 'probe'"

d1 "SELECT action, target, before_pointer, after_pointer, operator_id
    FROM control_audit WHERE action = 'routing_policy_publish'
    ORDER BY recorded_at DESC LIMIT 1"
```

**Expect:** R2 object is the document **as posted** (extra `ops_note` kept; schema-retained defaults kept). D1 row: `policy_id=probe`, `version=1` (TEXT), `content_pointer=control/routing-policy/probe/1.json`, `active_from` ISO now, `activated_by=platform-operator`, `canary_installation_ids` NULL, `status=published`. Audit `action=routing_policy_publish`, `target=probe@1`, `before_pointer` NULL, `after_pointer` equals the R2 key, `operator_id=platform-operator`. Publish derived the key from `document.policy_id` / `document.policy_version`, not `ai-platform/control/routing-policy/platform-default/`.

`status=published` is **not** served ([§9.3.7](#937-published-policy-is-not-served)).

#### 9.3.5 Duplicate publish leaves R2 unchanged

**Do:** post a different body for the same `(probe, 1)`:

```bash
python3 - <<'PY'
import json
doc=json.load(open("/tmp/rp-probe-v1.json"))
doc["document"]["rules"][0]["targets"][0]["provider_id"]="gemini"
json.dump(doc, open("/tmp/rp-probe-v1-conflict.json","w"))
PY
publish /tmp/rp-probe-v1-conflict.json
r2get "control/routing-policy/probe/1.json" /tmp/rp-probe-after-409.json
python3 - <<'PY'
import json
d=json.load(open("/tmp/rp-probe-after-409.json"))
assert d["rules"][0]["targets"][0]["provider_id"]=="deepseek"
print("r2 unchanged")
PY
d1 "SELECT COUNT(*) AS n FROM routing_policy WHERE policy_id='probe' AND version='1'"
d1 "SELECT COUNT(*) AS n FROM control_audit WHERE action='routing_policy_publish' AND target='probe@1'"
```

**Expect:** HTTP **409** `{ "error": "already_published" }`. R2 still names `deepseek` on the first target (existence check runs **before** R2.put). Still one D1 row and one publish audit — the duplicate did not insert.

#### 9.3.6 Latency warning and unreferenced policy

Visit summary’s bundled ref is `routing/standard` with `latencyClass: "standard"`. Publishing `standard@1` with only `"interactive"` targets must warn; publishing a copy of the checked-in fixture (catch-all, `latency_class: "standard"`, `overrides: []`) must not.

**Do:** mismatched `standard@1`, then replace it (delete is allowed on a throwaway DB; publish itself cannot overwrite):

```bash
python3 - <<'PY'
import json
doc=json.load(open("/tmp/rp-probe-v1.json"))
doc["document"]["policy_id"]="standard"
doc["document"]["policy_version"]=1
for rule in doc["document"]["rules"]:
    for t in rule["targets"]:
        t["features"]["latency_class"]="interactive"
json.dump(doc, open("/tmp/rp-standard-mismatch.json","w"))
PY
publish /tmp/rp-standard-mismatch.json
```

**Expect:** HTTP **200** `{ "warnings": ["latency_class_mismatch"] }`. Visit summary references `routing/standard` (policy id `standard`), so no `unreferenced_policy` warning — but no target `latency_class` equals its `"standard"`.

**Do:** delete that version and publish the aligned production shape (on-disk directory `platform-default` is historical; identity is `standard` / `1`):

```bash
d1 "DELETE FROM routing_policy WHERE policy_id='standard' AND version='1'"
r2del "control/routing-policy/standard/1.json"
cat > /tmp/rp-standard-v1.json <<'EOF'
{
  "document": {
    "schema_version": 1,
    "policy_id": "standard",
    "policy_version": 1,
    "defaults": { "cost_class": "standard", "max_parallel_attempts": 1 },
    "rules": [
      {
        "rule_id": "platform-default-fallback",
        "match": {},
        "requires": { "structured_output": false, "min_context_window": 0, "languages": [] },
        "targets": [
          {
            "provider_id": "deepseek",
            "model_id": "deepseek-v4-flash",
            "features": {
              "structured_output": true,
              "min_context_window": 128000,
              "languages": ["en"],
              "latency_class": "standard",
              "cost_class": "standard"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          },
          {
            "provider_id": "gemini",
            "model_id": "gemini-3.5-flash",
            "features": {
              "structured_output": true,
              "min_context_window": 128000,
              "languages": ["en"],
              "latency_class": "standard",
              "cost_class": "standard"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          }
        ]
      }
    ],
    "overrides": []
  }
}
EOF
publish /tmp/rp-standard-v1.json
r2get "control/routing-policy/standard/1.json" /tmp/rp-standard-stored.json
```

**Expect:** HTTP **200** `{}`. R2 key is `control/routing-policy/standard/1.json` (derived from the document), `policy_id` is `"standard"`, both targets advertise `latency_class: "standard"`, `overrides` is `[]`. D1 `status=published`.

#### 9.3.7 Published policy is not served

Config-cache serving reads `status='canary'` (cohort) else `status='active'` — never `published`.

**Do:** wait 31 s if this Worker already cached a miss, then:

```bash
invoke missing-policy-1
d1 "SELECT state, terminal_error_code, routing_decision FROM ai_request
    ORDER BY created_at DESC LIMIT 1"
d1 "SELECT status FROM routing_policy WHERE policy_id='standard' AND version='1'"
```

**Expect:** SSE `event: accepted` then `event: failed` with `data.code = "internal_error"` ([§8](#8-routing-failure-paths-post-accept) “no active/canary policy”). D1 `ai_request.state = 'Failed'`, `terminal_error_code = 'internal_error'`; synthetic `ai_attempt` via `settlePostAcceptInternalError`. Journal `routing_decision` is **NULL** — `selectCandidateChain` threw `ConfigCacheMissError` before `persistRoutingDecision`. Entitlement is still active; this is a routing miss, not `forbidden_capability`. `status` remains `published`.

#### 9.3.8 Canary failure paths

**Do:**

```bash
curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/1/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d 'not json{'
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/1/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}'
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/1/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"installation_ids":[]}'
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/1/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"installation_ids":["00000000-0000-4000-8000-000000000000"]}'
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/does-not-exist/versions/1/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"installation_ids\":[\"$INSTALLATION_ID\"]}"
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/99/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"installation_ids\":[\"$INSTALLATION_ID\"]}"
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/99/promote" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
echo; cat /tmp/rp-http-body.json; echo

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/99/rollback" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
echo; cat /tmp/rp-http-body.json; echo
```

**Expect:** malformed JSON → **400** `{ "error": "invalid_json" }`. Missing or non-array `installation_ids` → **400** `{ "error": "missing_installation_ids" }`. Empty `installation_ids` → **400** `{ "error": "missing_installation_ids" }`. Unknown installation → **404** `{ "error": "installation_not_found" }`. Unknown policy id or version → **404** `{ "error": "policy_version_not_found" }` on canary, promote, and rollback. `standard@1` is still `published`.

#### 9.3.9 Canary success and serving split

Publish a distinct v2 (gemini-first) so the cohort’s chain differs from v1, then canary v2 onto **I0**.

**Do:**

```bash
python3 - <<'PY'
import json
doc=json.load(open("/tmp/rp-standard-v1.json"))
doc["document"]["policy_version"]=2
doc["document"]["rules"][0]["rule_id"]="canary-gemini-first"
doc["document"]["rules"][0]["targets"].reverse()
json.dump(doc, open("/tmp/rp-standard-v2.json","w"))
PY
publish /tmp/rp-standard-v2.json

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/2/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"installation_ids\":[\"$INSTALLATION_ID\"],\"cohort_name\":\"verify-cohort\"}"
echo; cat /tmp/rp-http-body.json; echo

d1 "SELECT version, status, canary_installation_ids FROM routing_policy
    WHERE policy_id='standard' ORDER BY version"
```

**Expect:** publish HTTP **200** with body `{}` — no `unreferenced_policy` warning even though the manifest ref is id-only (`routing/standard`); canary **200** `{}`. v2 `status=canary`, `canary_installation_ids` is the JSON array `[I0]` (string ids). `cohort_name` is persisted in the latest `routing_policy_canary` audit `after_pointer` under `details.cohort_name` (not a D1 column). v1 remains `published` (still not globally served).

v2 is not globally active yet, so a non-cohort installation has **no** active row. Promote v1 first so others have a fallback, then keep v2 as canary:

```bash
curl -sS -o /tmp/rp-http-body.json -D - -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/1/promote" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
echo; cat /tmp/rp-http-body.json; echo

curl -sS -o /tmp/rp-http-body.json -D - -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/2/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"installation_ids\":[\"$INSTALLATION_ID\"]}"
echo; cat /tmp/rp-http-body.json; echo
```

Promote of v1 supersedes other canary/active on this `policy_id`, so the second canary call puts v2 back on the cohort. Wait 31 s.

**Do:** `invoke canary-i0-1` as **I0**.

**Expect:** `routing_decision.policy_version = 2`, `chain[0].provider_id = "gemini"` (canary document). `rule_id = "canary-gemini-first"`.

If you can mint an AAT for **I1** and invoke: `policy_version = 1`, `chain[0].provider_id = "deepseek"`. D1 picks **which version**; the bundled ref stays `routing/standard` on both.

#### 9.3.10 Promote to active

**Do:** promote the canary (v2). Body is empty.

```bash
curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/2/promote" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
echo; cat /tmp/rp-http-body.json; echo

d1 "SELECT version, status, canary_installation_ids FROM routing_policy
    WHERE policy_id='standard' ORDER BY rowid"

d1 "SELECT before_pointer, after_pointer FROM control_audit
    WHERE action='routing_policy_promote' ORDER BY recorded_at DESC LIMIT 1"

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/2/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"installation_ids\":[\"$INSTALLATION_ID\"]}"
echo; cat /tmp/rp-http-body.json; echo
```

**Expect:** promote 200 `{}`. v2 `status=active`, `canary_installation_ids` NULL. v1 `status=superseded`, canary ids NULL. Audit `after_pointer=standard@2`, `before_pointer=standard@1`. Canary on already-active v2 → **409** `{ "error": "illegal_policy_transition" }`. Promote of an already-active or superseded version → **409** `{ "error": "illegal_policy_transition" }` (no silent 200).

Wait 31 s, `invoke after-promote-v2`. **Expect:** `policy_version = 2` for **I0**. Manifest picks the playbook **id** (`routing/standard`); D1 `active`/`canary` picks the **version**.

#### 9.3.11 Rollback and version tie-break

**Do:** rollback the active v2 (prior superseded is v1):

```bash
curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/2/rollback" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
echo; cat /tmp/rp-http-body.json; echo
d1 "SELECT version, status FROM routing_policy WHERE policy_id='standard'"
```

**Expect:** 200. v2 `superseded`, v1 `active`.

**Do:** rollback of active with **no** superseded row:

```bash
d1 "UPDATE routing_policy SET status='published' WHERE policy_id='standard' AND version='2'"
curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/1/rollback" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
echo; cat /tmp/rp-http-body.json; echo
```

**Expect:** **409** `{ "error": "illegal_policy_transition" }` (no `status='superseded'` row to resurrect). Rollback of a `published` or `superseded` row (not `canary`/`active`) → **409** `{ "error": "illegal_policy_transition" }`. Restore v2 to superseded:

```bash
d1 "UPDATE routing_policy SET status='superseded' WHERE policy_id='standard' AND version='2'"
```

**Do:** canary v2 again, then rollback the **canary** (not the active):

```bash
curl -sS -o /dev/null -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/2/canary" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"installation_ids\":[\"$INSTALLATION_ID\"]}"

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/2/rollback" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
echo; cat /tmp/rp-http-body.json; echo
d1 "SELECT version, status, canary_installation_ids FROM routing_policy WHERE policy_id='standard'"
```

**Expect:** v2 returns to `published`, `canary_installation_ids` NULL. v1 stays `active`.

**Do:** TEXT sort vs `rowid` tie-break. Insert versions `"9"` and `"10"` with the **same** `active_from`, `"10"` later (higher `rowid`), both `superseded`; promote a new v11; rollback v11.

```bash
python3 - <<'PY'
import json
doc=json.load(open("/tmp/rp-standard-v1.json"))
for ver, first in [(9,"deepseek"),(10,"gemini"),(11,"deepseek")]:
    d=json.loads(json.dumps(doc))
    d["document"]["policy_version"]=ver
    d["document"]["rules"][0]["targets"][0]["provider_id"]=first
    json.dump(d, open(f"/tmp/rp-standard-v{ver}.json","w"))
PY
publish /tmp/rp-standard-v9.json
publish /tmp/rp-standard-v10.json
publish /tmp/rp-standard-v11.json

d1 "UPDATE routing_policy SET status='superseded', active_from='2026-08-03T12:00:00.000Z'
    WHERE policy_id='standard' AND version IN ('9','10')"
d1 "UPDATE routing_policy SET status='active', active_from='2026-08-03T12:01:00.000Z'
    WHERE policy_id='standard' AND version='11'"
# Ensure rowid order: 9 then 10. Re-insert 10 last if needed by deleting/re-adding 10 only.

curl -sS -D - -o /tmp/rp-http-body.json -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/11/rollback" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
echo; cat /tmp/rp-http-body.json; echo

d1 "SELECT version, status FROM routing_policy WHERE policy_id='standard' AND status='active'"
d1 "SELECT before_pointer, after_pointer FROM control_audit
    WHERE action='routing_policy_rollback' ORDER BY recorded_at DESC LIMIT 1"
```

**Expect:** active version is `10`, not `9`. Lexical TEXT `"9" > "10"` would have picked 9; `ORDER BY active_from DESC, rowid DESC` picks the later-inserted same-timestamp superseded row. Restore a clean active v1 before continuing:

```bash
d1 "UPDATE routing_policy SET status='superseded', canary_installation_ids=NULL
    WHERE policy_id='standard'"
d1 "UPDATE routing_policy SET status='active' WHERE policy_id='standard' AND version='1'"
```

Wait 31 s.

#### 9.3.12 Manifest link and independent switches

**Do:** prove the capability manifest is not in D1/R2, and that routing control did not entitle or enroll.

```bash
python3 - <<'PY'
import json
m=json.load(open("manifests/published/clinic.visit_summary@1.0.0.json"))
assert m["Routing"]["routingPolicyRef"]=="routing/standard"
assert m["Routing"]["latencyClass"]=="standard"
assert m["Routing"]["requiredProviderFeatures"]["language"]=="en"
assert m["Routing"]["requiredProviderFeatures"]["contextWindow"]==32000
assert m["Output"]["mode"]=="prose"
assert "freshnessHint" not in json.dumps(m["Context requirements"])
print("manifest ok")
PY

d1 "SELECT COUNT(*) AS n FROM routing_policy WHERE content_pointer LIKE '%visit_summary%'"
d1 "SELECT status, request_quota, allowed_capabilities FROM entitlement
    WHERE installation_id = '$INSTALLATION_ID'"
d1 "SELECT installation_id, status FROM installation WHERE installation_id = '$INSTALLATION_ID'"
```

**Expect:** checked-in JSON has the ten groups and `routingPolicyRef` `routing/standard` (playbook id `standard` only — no version in the ref). No D1 pointer names the manifest file. Entitlement still `active` with the quotas you set in Stage 4 — publish/canary/promote/rollback did not rewrite it. `installation.status` unchanged.

**Do:** `r2get "control/pricing/platform-default/1.json" /tmp/price.json` (may miss locally unless you uploaded it).

**Expect:** that object is **not** the routing document. Routing R2 lives only under `control/routing-policy/…`. Pricing is bundled for settlement ([Stage 11](13-stage-11-terminal-settlement.md)), never client-visible on this path.

#### 9.3.13 Missing R2 document

**Do:** keep the active D1 row, delete the object, wait 31 s, invoke:

```bash
r2del "control/routing-policy/standard/1.json"
invoke missing-r2-1
d1 "SELECT state, terminal_error_code, routing_decision FROM ai_request
    ORDER BY created_at DESC LIMIT 1"
```

**Expect:** SSE `failed` `internal_error` ([§8](#8-routing-failure-paths-post-accept) “R2 document missing”). D1 `state = 'Failed'`, `terminal_error_code = 'internal_error'`. `routing_decision` NULL. Restore the object from the file you published:

```bash
python3 - <<'PY'
import json
json.dump(json.load(open("/tmp/rp-standard-v1.json"))["document"],
          open("/tmp/rp-standard-v1-body.json","w"))
PY
r2put "control/routing-policy/standard/1.json" /tmp/rp-standard-v1-body.json
```

Wait 31 s.

#### 9.3.14 Router identity schema and catch-all

Publish validates only identity shape ([§6.1](#61-publish-post-controlrouting-policiespublish)) — not catch-all or `schema_version`. Overwrite R2 in place (D1 still says `standard` / `1`).

**Do:** identity mismatch in the **document** vs D1 row:

```bash
python3 - <<'PY'
import json
d=json.load(open("/tmp/rp-standard-v1-body.json"))
d["policy_id"]="other"
json.dump(d, open("/tmp/rp-bad-identity.json","w"))
PY
r2put "control/routing-policy/standard/1.json" /tmp/rp-bad-identity.json
```

Wait 31 s, `invoke bad-identity-1`.

**Expect:** SSE `failed` `internal_error`. D1 `state = 'Failed'`, `terminal_error_code = 'internal_error'`. The router threw `RoutingPolicyError` `policy_identity_mismatch`; `runFreshEventSource`’s catch maps unexpected throws to taxonomy `internal_error` on the wire only. `routing_decision` stays NULL (throw is before persist). Worker logs name the mismatch.

**Do:** `schema_version: 99`, then a document whose last rule is **not** a catch-all:

```bash
python3 - <<'PY'
import json
d=json.load(open("/tmp/rp-standard-v1-body.json"))
d["schema_version"]=99
json.dump(d, open("/tmp/rp-bad-schema.json","w"))
d=json.load(open("/tmp/rp-standard-v1-body.json"))
d["rules"][0]["match"]={"capability_ids":["clinic.other"]}
json.dump(d, open("/tmp/rp-no-catchall.json","w"))
PY
r2put "control/routing-policy/standard/1.json" /tmp/rp-bad-schema.json
```

Wait 31 s, `invoke bad-schema-1`. Then put `/tmp/rp-no-catchall.json`, wait 31 s, `invoke no-catchall-1`.

**Expect:** both SSE `failed` `internal_error` (`unsupported_schema_version`, `missing_catch_all`). Restore the aligned body and wait 31 s:

```bash
r2put "control/routing-policy/standard/1.json" /tmp/rp-standard-v1-body.json
```



#### 9.3.15 RoutingDecision on a routed request

**Do:** `invoke happy-decision-1` and inspect the journal JSON (every [§7](#7-router-output-routingdecision-every-field) field):

```bash
d1 "SELECT routing_tier, routing_decision FROM ai_request ORDER BY created_at DESC LIMIT 1"
```

**Expect:** `routing_decision` is non-null JSON on the **existing** `ai_request` row (one UPDATE, no new table). Fields:

- `policy_id = "standard"`, `policy_version = 1`
- `rule_id = "platform-default-fallback"` (the catch-all `match: {}`)
- `effective_cost_class = "standard"`
- `cost_class_source = "manifest"` (hardcoded `manifestCostClass: "standard"` is stricter than hardcoded `entitlementMaxCostClass: "premium"`; `defaults.cost_class` is **not** this value — the published default may be `"standard"` too, but [§9.3.4](#934-first-publish-and-storage-inspection) stored `"premium"` on `probe` and that never became the effective class)
- `routing_tier = "standard"` and equals column `ai_request.routing_tier` — **not** `"degraded"`, even though the body sent `routing_tier` / `degraded` / `degraded_notice`
- `required_features.structured_output_required = false` (`Output.mode` is `prose`)
- `required_features.min_context_window = 32000` (manifest `contextWindow`, not the rule’s `0`)
- `required_features.languages = ["en"]`
- `required_features.latency_class = "standard"`
- `chain` length 2: ordinal `0` `deepseek` / `deepseek-v4-flash` `max_attempts=2` `timeout_ms=30000`, then ordinal `1` `gemini` / `gemini-3.5-flash` same bounds
- `excluded` is `[]`
- **No** `max_parallel_attempts` key on the JSON

The request may later `completed` or `failed` at the provider; the decision is already on the row **before** invoke. Sequential walk: `ai_attempt` rows (if any) follow chain order, one target at a time.

#### 9.3.16 Match clauses and requirement floors

Publish `standard@3` with a specific first rule plus catch-all, promote it, wait 31 s.

**Do:**

```bash
cat > /tmp/rp-standard-v3.json <<EOF
{
  "document": {
    "schema_version": 1,
    "policy_id": "standard",
    "policy_version": 3,
    "defaults": { "cost_class": "standard", "max_parallel_attempts": 1 },
    "rules": [
      {
        "rule_id": "visit-en-standard",
        "match": {
          "capability_ids": ["clinic.visit_summary"],
          "installation_ids": ["$INSTALLATION_ID"],
          "cost_classes": ["standard"],
          "tiers": ["standard"],
          "languages": ["en"],
          "latency_classes": ["standard"]
        },
        "requires": {
          "structured_output": true,
          "min_context_window": 64000,
          "languages": ["en", "ar"]
        },
        "targets": [
          {
            "provider_id": "deepseek",
            "model_id": "deepseek-v4-flash",
            "features": {
              "structured_output": false,
              "min_context_window": 128000,
              "languages": ["en"],
              "latency_class": "standard",
              "cost_class": "standard"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          },
          {
            "provider_id": "gemini",
            "model_id": "gemini-3.5-flash",
            "features": {
              "structured_output": true,
              "min_context_window": 128000,
              "languages": ["en", "ar"],
              "latency_class": "standard",
              "cost_class": "standard"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          }
        ]
      },
      {
        "rule_id": "catch-all",
        "match": {},
        "requires": { "structured_output": false, "min_context_window": 0, "languages": [] },
        "targets": [
          {
            "provider_id": "deepseek",
            "model_id": "deepseek-v4-flash",
            "features": {
              "structured_output": true,
              "min_context_window": 128000,
              "languages": ["en"],
              "latency_class": "standard",
              "cost_class": "standard"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          }
        ]
      }
    ],
    "overrides": []
  }
}
EOF
publish /tmp/rp-standard-v3.json
curl -sS -o /dev/null -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/3/promote" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

Wait 31 s, `invoke match-floors-1`.

**Expect:** `rule_id = "visit-en-standard"` (first match wins: capability, installation, effective cost `standard`, tier `standard`, language `en`, latency `standard`). Merged floor: structured **true** (rule OR; manifest prose is false), `min_context_window = 64000` (`Math.max(32000, 64000)`), languages **union** `en`+`ar`. `required_features` on the journal still shows **manifest-only** (`structured_output_required: false`, `min_context_window: 32000`, `languages: ["en"]`) — filtering used the merged floor. DeepSeek is `excluded` `feature_unsupported` (`structured_output: false`). Gemini stays in `chain[0]`.

**Do:** a first rule that **fails** `match.languages` (rule list `["ar"]` vs request `en`) by publishing v3-style with `languages:["ar"]` only on the first rule (or temporarily put that R2 and wait). Simpler: first rule `installation_ids: ["$OTHER_INSTALLATION_ID"]` only.

Put a document whose first `match.installation_ids` is **I1** only, promote, wait, invoke as **I0**.

**Expect:** `rule_id = "catch-all"` (first rule skipped; empty match wins).

**Do:** degraded tier. Soft-threshold is Stage 4’s switch, consumed here as `match.tiers`. After [§9.3.15](#9315-routingdecision-on-a-routed-request) at least one request has been journaled; force the next admission over the line on this throwaway DB:

```bash
d1 "UPDATE entitlement SET soft_threshold = 0.0001
    WHERE installation_id = '$INSTALLATION_ID'"
```

Wait 31 s, `invoke degraded-tier-1`.

**Expect:** SSE `accepted` includes `degraded_notice: true`. `ai_request.routing_tier = "degraded"` **and** `routing_decision.routing_tier = "degraded"`. The first rule’s `match.tiers` is only `["standard"]`, so this request skips it and takes `rule_id = "catch-all"`. Client still cannot force this by sending `routing_tier` in the body ([§9.3.15](#9315-routingdecision-on-a-routed-request)). Restore a sane threshold afterwards (`UPDATE … SET soft_threshold = 0.8` or whatever Stage 4 wrote).

#### 9.3.17 Overrides and cost class

**Do:** publish/promote `standard@4` with two catch-all targets (`economy` DeepSeek, `premium` Gemini) and three stacked override keys for **I0** (narrowing only):

```bash
cat > /tmp/rp-standard-v4.json <<EOF
{
  "document": {
    "schema_version": 1,
    "policy_id": "standard",
    "policy_version": 4,
    "defaults": { "cost_class": "premium", "max_parallel_attempts": 1 },
    "rules": [
      {
        "rule_id": "catch-all",
        "match": {},
        "requires": { "structured_output": false, "min_context_window": 0, "languages": [] },
        "targets": [
          {
            "provider_id": "deepseek",
            "model_id": "deepseek-v4-flash",
            "features": {
              "structured_output": true,
              "min_context_window": 128000,
              "languages": ["en"],
              "latency_class": "standard",
              "cost_class": "economy"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          },
          {
            "provider_id": "gemini",
            "model_id": "gemini-3.5-flash",
            "features": {
              "structured_output": true,
              "min_context_window": 128000,
              "languages": ["en"],
              "latency_class": "standard",
              "cost_class": "premium"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          }
        ]
      }
    ],
    "overrides": [
      {
        "installation_id": "$INSTALLATION_ID",
        "exclude_providers": ["gemini"],
        "force_cost_class": "economy"
      },
      {
        "installation_id": "$INSTALLATION_ID",
        "pin_target": { "provider_id": "gemini", "model_id": "gemini-3.5-flash" }
      }
    ]
  }
}
EOF
publish /tmp/rp-standard-v4.json
curl -sS -o /dev/null -X POST \
  "$GATEWAY/control/routing-policies/standard/versions/4/promote" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN"
```

Wait 31 s, `invoke override-1`.

**Expect:** first override wins (`.find()`). `cost_class_source = "installation_override"`, `effective_cost_class = "economy"` (min of standard, premium, economy). Gemini is `installation_excluded` (`exclude_providers`) — the second override never runs, so `pin_target` does not resurrect Gemini (overrides cannot widen). Premium would also have been `cost_class_excluded` if it had survived exclude. DeepSeek remains. `defaults.cost_class: "premium"` did **not** become the effective class.

**Do:** publish a variant whose only override is `pin_target` to `{ "provider_id": "missing", "model_id": "nope" }`, promote, invoke.

**Expect:** `chain = []`, both real targets `installation_excluded`, SSE `failed` `provider_unavailable`, **persisted** `routing_decision` (empty-chain is not a throw).

#### 9.3.18 Target exclusions and empty chain

**Do:** publish/promote a catch-all whose first target is malformed and whose second is well-formed but language-insufficient; include a third well-formed `en` target so the chain is not empty yet:

```bash
cat > /tmp/rp-standard-v5.json <<'EOF'
{
  "document": {
    "schema_version": 1,
    "policy_id": "standard",
    "policy_version": 5,
    "defaults": { "cost_class": "standard", "max_parallel_attempts": 1 },
    "rules": [
      {
        "rule_id": "catch-all",
        "match": {},
        "requires": { "structured_output": false, "min_context_window": 0, "languages": [] },
        "targets": [
          {
            "provider_id": "deepseek",
            "model_id": "deepseek-v4-flash",
            "features": {
              "structured_output": true,
              "languages": ["en"],
              "latency_class": "standard",
              "cost_class": "standard"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          },
          {
            "provider_id": "gemini",
            "model_id": "gemini-3.5-flash",
            "features": {
              "structured_output": true,
              "min_context_window": 128000,
              "languages": ["fr"],
              "latency_class": "standard",
              "cost_class": "standard"
            },
            "max_attempts": 2,
            "timeout_ms": 30000
          }
        ]
      }
    ],
    "overrides": []
  }
}
EOF
```

The first target **omits** `min_context_window` (publish still accepts it). Promote v5, wait 31 s, `invoke malformed-1`.

**Expect:** DeepSeek `excluded.reason_code = "feature_unsupported"` (missing window). Gemini `language_unsupported` (declared list, missing `en`). `chain = []`, SSE `failed` `provider_unavailable`, **not** `internal_error`. Decision is persisted.

**Do:** add targets that isolate the other fail-closed codes (put R2, wait 31 s, invoke each time, or combine siblings):

- `cost_class: "standrd"` (typo) → `feature_unsupported`; a sibling `"premium"` with effective `standard` → `cost_class_excluded`
- `languages` as a string `"en"` (non-array) → `feature_unsupported` (does not throw)
- `latency_class: "interactive"` vs manifest `"standard"` → `feature_unsupported` (no `latency_unsupported`)
- `min_context_window: 1000` (declared but too small vs merged 32000) → `context_window_too_small`

**Expect:** each distinct code as above. A well-formed sibling stays in `chain`. Publish-time target-shape check remains absent — this is the request-path defense.

#### 9.3.19 Provider kill switch failover

Restore aligned `standard@1` as active (or publish v6 = production fixture), wait 31 s.

**Do:** arm the provider kill via the control route (preferred over raw D1):

```bash
curl -sS -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/kill-switches/arm" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"scope":"provider","target":"deepseek"}'
```

Wait 31 s, `invoke kill-deepseek-1`.

**Expect:** HTTP **200** `{}` from arm. SSE does **not** 503 `capability_disabled`. `excluded` contains DeepSeek with `reason_code = "kill_switch"`. `chain[0]` is Gemini (document order, failover). Provider kills are D1 `kill_switch`, not an R2 field.

**Do:**

```bash
curl -sS -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/kill-switches/disarm" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"scope":"provider","target":"deepseek"}'

curl -sS -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/kill-switches/arm" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"scope":"global","target":"global"}'
invoke kill-global-1

curl -sS -w '\nHTTP %{http_code}\n' -X POST \
  "$GATEWAY/control/kill-switches/disarm" \
  -H "Authorization: Bearer $OPERATOR_BEARER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"scope":"global","target":"global"}'
```

**Expect:** HTTP JSON **503** `capability_disabled` **before** SSE — capability-level kill never reaches `selectCandidateChain`. No new `routing_decision`. Disarm returns **200** `{}`.

#### 9.3.20 What this stage does not do

**Do:** confirm the non-routing groups never appear on `routing_decision`, and that control did not mint tokens or call a provider by itself.

```bash
d1 "SELECT routing_decision FROM ai_request ORDER BY created_at DESC LIMIT 1"
```

**Expect:** JSON has only [§7](#7-router-output-routingdecision-every-field) keys — no Access, Prompt binding, Economics, Governance, Interaction, Input, or Context requirements. `required_features.structured_output_required` follows `Output.mode`, not `Routing.requiredProviderFeatures.structuredOutput` (visit summary declares `structuredOutput: false` and `mode: "prose"`; [§9.3.16](#9316-match-clauses-and-requirement-floors) already forced structured via **rule** `requires`). `degradedTierPolicy` is not a decision field. Economics `perRequestTokenCeiling` did not become `effective_cost_class` (hardcoded `"standard"` / `"premium"`).

**Do:** `POST /control/routing-policies/…/publish` does not insert `ai_request` or `ai_attempt`.

**Expect:** those tables only grow on `POST /v1/requests`. This stage writes `routing_policy`, R2 `control/routing-policy/…`, and `control_audit`. It does not enroll, entitle, or mint an AAT.

#### 9.3.21 Unreachable and operator-hostile paths

These claims are in the file and in code; a healthy local Worker cannot induce them as a stable live probe.

- **Metaphor** ([§2](#2-metaphor)) is not an HTTP/storage assertion.
- `no_matching_rule`**:** `validatePolicyDocument` requires a catch-all last rule, and a catch-all matches every request, so `selectCandidateChain` cannot throw `no_matching_rule` after validation. [§9.3.14](#9314-router-identity-schema-and-catch-all) already shows the missing-catch-all wrap.
- `rule_id` **uniqueness** is not enforced: publishing two rules with the same `rule_id` still 200s; journal attribution would be ambiguous. Ops discipline only.
- **Concurrent first publish** UNIQUE race: both winners map to 409 `already_published`. Two-curl timing is not a reliable probe; the sequential duplicate in [§9.3.5](#935-duplicate-publish-leaves-r2-unchanged) is the operator-visible 409.
- `storage_error`**:** any D1 failure other than UNIQUE. Do not sabotage the database.
- `missing_r2_binding`**:** Worker started without an R2 binding. This environment has one.
- **Bundled-manifest extra keys** (`freshnessHint`): rejected at Worker **build/load**, not via control publish. Changing `clinic.visit_summary@1.0.0.json` and rebuilding is out of band for this stage.

---

