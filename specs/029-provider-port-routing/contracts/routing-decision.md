# Routing policy interpretation and selection reason (D2)

Frozen routing-policy-as-data contract: interpretation of a versioned routing
policy document into an ordered **candidate chain** of provider+model targets,
plus the request-level **selection reason** / `routing_decision` object. Later
slices **D3** (invocation), **D5/D7** (real targets), **F4** (soft-threshold
signal), and **J3** (policy activation) **consume** this artifact — they must
not consult provider history when building the chain and must not replace
policy-as-data with code-path conditionals.

**Source of truth in code (this slice):** `ai-platform/src/router/index.ts`.

**Traces to:** spec Freezes (routing-policy-as-data); FR-007–FR-012; architecture
§4.3.7, §7.3.

---

## 1. Overview

The provider router selects an ordered candidate chain from routing policy using
capability requirements (structured output support, context window, language,
latency class), installation overrides, cost class, and — where a soft quota
threshold was crossed — a degraded tier. Policy is data, versioned and auditable,
not conditionals in the code path. Routing is **stateless**: the chain depends
only on the capability, the policy, and this request. There is no circuit breaker
and no shared provider-health state (§4.3.7).

The §7.3 `routing_policy` entity (policy id, version, content pointer,
active_from, activated_by) is Consumed from A5 unchanged. D2 interprets policy
**content**; it does not migrate columns.

---

## 2. Policy document (interpretation shape)

The active version's document is held in the config cache under kind
`active_routing_policy` (§4.3.7, §4.4; A5 Freezes). D2's router reads it through
that cache contract. Unit tests supply the parsed document via a fake/spy
`ConfigCache` preloaded under `active_routing_policy` (Clarification Q3). D2 does
not implement R2 policy-document fetch.

| Field | Type / values | Notes |
| --- | --- | --- |
| `schema_version` | integer | Document format version; independent of `policy_version` |
| `policy_id`, `policy_version` | string, integer | Must equal the owning `routing_policy` row |
| `defaults` | `{ cost_class, max_parallel_attempts }` | Applied when a rule omits them |
| `rules[]` | ordered, **first match wins** | Empty match set matches everything; document must end with a catch-all rule |
| `rules[].rule_id` | string, unique in document | Recorded in the selection reason |
| `rules[].match` | `{ capability_ids[], installation_ids[], cost_classes[], tiers[], languages[], latency_classes[] }` — all optional; all present clauses must hold | `tiers[]` takes `standard` / `degraded` |
| `rules[].requires` | `{ structured_output: bool, min_context_window: int, languages[] }` | Feature floor a target must satisfy |
| `rules[].targets[]` | ordered `{ provider_id, model_id, features, max_attempts, timeout_ms }` | `model_id` is a pinned version, never a floating alias (R-4); `features` mirrors `requires` and is what the filter reads |
| `rules[].max_parallel_attempts` | integer `1`–`6`, default `1` | Speculative parallelism, hard-bounded by the per-request outgoing-connection cap of six (§4.3.8) |
| `overrides[]` | `{ installation_id, exclude_providers[], pin_target, force_cost_class }` | Applied after rule selection, before feature filtering; may narrow the chain, never widen it beyond the matched rule's targets |

---

## 3. Router inputs

| Input | Source | Notes |
| --- | --- | --- |
| Active policy document | A5 config cache (`active_routing_policy`) | Versioned data, not code conditionals (FR-009; T19) |
| Capability requirements | Request/capability fixture inputs named by §4.3.7 | Structured output support, context window, language, latency class, degraded-tier policy; D2 does not load manifests |
| Installation id | Request context | Selects matching overrides |
| Cost-class sources | Manifest Routing group ceiling, entitlement `max_cost_class`, installation `force_cost_class` | Effective class is the **lowest** of the three; router records which source bound it (§4.3.7) |
| Routing tier | In-memory request signal: `standard` or `degraded` | Soft-threshold *detection* is F4; D2 only matches `rules[].match.tiers` when the signal is already set (FR-008; T17) |

Cost class is an ordered enum: `economy` < `standard` < `premium`. It is never
supplied by the client (§3.4).

---

## 4. Candidate chain and selection reason

### 4.1 Candidate chain

An ordered list of `{ provider_id, model_id }` targets (plus any per-target
fields the matched rule's `targets[]` carries that D3 needs for attempt bounds).
An empty chain after filtering is permitted; invoking it and emitting
`provider_unavailable` is D3.

### 4.2 Request-level `routing_decision` (selection reason)

Recorded on the request (FR-010). D2 asserts the object is present on the routing
outcome; persisting it into D1/R2 is C3's concern and must not invent a new
`ai_request` column here.

| Field | Contents |
| --- | --- |
| `policy_id` | Active policy id |
| `policy_version` | Active policy version |
| `rule_id` | Matched rule |
| `effective_cost_class` | Lowest of the three sources |
| `cost_class_source` | `manifest` / `entitlement_cap` / `installation_override` |
| `routing_tier` | `standard` / `degraded` |
| `required_features` | Capability requirements applied |
| `chain` | Ordered `{ ordinal, provider_id, model_id, max_attempts, timeout_ms }[]` — `max_attempts` / `timeout_ms` are carried through unchanged from the matched rule's `targets[]` (§2), so D3 bounds attempts without re-reading policy or inventing caps |
| `excluded` | `{ provider_id, model_id, reason_code }[]` |
| `max_parallel_attempts` | Integer `1`–`6` |

`reason_code` takes: `feature_unsupported`, `context_window_too_small`,
`language_unsupported`, `kill_switch`, `installation_excluded`, or
`cost_class_excluded`.

Attempt-level `selection_reason` enums (`primary`,
`fallback_after_retryable_error`, …) are owned by D3's walk through the chain;
D2 freezes the request-level object that explains the chain.

### 4.3 Filtering (one case each)

| Filter | Excludes targets that… |
| --- | --- |
| Structured output support | Lack structured output support when required |
| Context window | Fall below the required minimum |
| Language | Do not satisfy the required language |
| Latency class | Fall outside the required latency class |
| Installation override | Are excluded / re-pinned / cost-forced by the override |
| Cost class | Fall outside the effective cost class |
| Degraded tier | Fail to match when `routing_tier = degraded` |

### 4.4 Outgoing-connection cap (T20)

`max_parallel_attempts` MUST be an integer in `1`–`6`. A policy document that
requests speculative parallelism beyond six is rejected or clamped to the cap —
the per-request outgoing-connection cap of six is the hard bound (§4.3.8).

---

## 5. Stateless invariants

| Invariant | Test |
| --- | --- |
| Identical capability, policy, and request inputs → identical candidate chain | T13 |
| A prior provider failure does not change the next request's chain — no provider history consulted | T15 |
| No circuit breaker; no shared provider-health state | FR-011; Out of Scope |
| No per-request Durable Object or other server-side request state | Edge Cases |

---

## 6. Consumers

| Slice | Binding |
| --- | --- |
| **D3** | Walks the candidate chain with bounded retry/fallback; journals attempts |
| **D5 / D7** | Real provider+model targets appear in policy data; pipeline unchanged |
| **F4** | Sets the degraded-tier signal the router already matches |
| **J3** | Activates a new `routing_policy` version; D2 reads whatever is active |

Later slices MUST **consume** this artifact. They may extend activation and
soft-threshold detection; they must not rewrite policy-as-data selection or add
health-based routing (§9.14 / R-20).

---

## 7. Verification

| Test | Asserts |
| --- | --- |
| T7 | Chain ordered by policy |
| T8–T11 | One filtering case per capability requirement |
| T12 | Installation override applied |
| T13 | Identical inputs → identical chain |
| T14 | Selection reason recorded |
| T15 | Prior failure does not change next chain |
| T16 | Cost class participates in selection |
| T17 | Soft-threshold signal selects degraded tier |
| T19 | Active policy read as versioned `routing_policy` data |
| T20 | Speculative parallelism bounded by outgoing-connection cap of six |
