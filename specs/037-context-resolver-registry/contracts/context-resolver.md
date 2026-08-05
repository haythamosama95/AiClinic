# Contract: Context Resolver key-list API (E3)

**Frozen by:** Slice E3 — Context Resolver registry, first context RPC, and client contract test  
**Implements:** §4.1 Context Resolver, §5.2 Shape (client assembly), §13.5 Client contract tests of
`docs/architecture/17-ai-platform.md`  
**Status:** Frozen. Later slices (E4, H3, J2) **consume** this artifact; they extend the registered
key set, never rewrite the key-list API, the unknown-key typed failure, the no-capability-id rule,
or the screen-scoped cache lifetime. H3 may add an arguments-aware `resolveRequests` channel as a
compatible extension ([§2.4](#24-arguments-aware-extension-h3-allowed)) without removing
`resolve(List<String> keys)`.

**Source of truth in code (this slice):** `frontend/lib/core/ai/context_resolver.dart`,
`frontend/lib/core/ai/context_registration.dart`.

**Traces to:** spec **Freezes** (Context Resolver; generic key-list API; screen-scoped cache);
FR-001–FR-005, FR-007.

---

## 1. Overview

The Context Resolver is a **generic registry** — context key → resolver function — that maps each
requested key to the clinic Supabase RPC/query that produces it, assembles a payload conforming to
each key’s platform-published shape, and caches short-lived results within a screen. It never sees a
capability id and never branches on one.

---

## 2. Key-list API

### 2.1 Input

| Aspect | Rule |
| --- | --- |
| Parameter | An ordered list of context keys (`domain.concept@vN` strings). |
| Capability id | **Absent.** The public API MUST NOT accept a capability id and MUST NOT branch on one. |

`resolve(List<String> keys)` remains the frozen E3 surface. It is implemented as a thin wrapper
over the H3 arguments-aware channel ([§2.4](#24-arguments-aware-extension-h3-allowed)) that passes
empty/null arguments per key.

### 2.2 Success output — assembled payload

On success, the Resolver returns a single **JSON object** (Dart `Map<String, Object?>` on the
client) whose keys are exactly the requested context keys (no extras) and whose values are the
per-key payloads conforming to each key’s A5-published shape.

```json
{
  "visit.chief_complaint@v1": {
    "visit_id": "550e8400-e29b-41d4-a716-446655440000",
    "complaint": "Persistent headache for three days.",
    "recorded_at": "2026-07-31T12:00:00.000Z"
  }
}
```

Field names, types, cardinality, and units for each value are owned by A5
(`specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md`). E3 does not redefine them.

### 2.3 Failure output — typed failures (closed set)

The Resolver MUST surface a **typed failure** and MUST NOT return a partial payload as success.
Inventing data for an unknown key is forbidden (§4.1 Must not: send unrequested data).

| `code` | When | Fields |
| --- | --- | --- |
| `unknown_context_key` | Any requested key has no registered resolver (checked before any resolution). | `unknownKey` set to the offending key; `failedKey` null. |
| `resolution_failed` | A registered key’s resolver/port throws (RPC failure, network, malformed payload). | `failedKey` set to the key that failed; `unknownKey` null. |

| Outcome | Meaning |
| --- | --- |
| Typed failure | One of the closed codes above. |
| Partial success | **Forbidden.** |
| Raw exception escape | **Forbidden** for registered-key resolution errors — normalize to `resolution_failed`. |

This slice emits **no** §5.4 taxonomy codes for Resolver failures (spec Edge Cases). Adding
`resolution_failed` is a **contract extension** of the unknown-key rule, not a rewrite of it.

### 2.4 Arguments-aware extension (H3, allowed)

H3 may add an arguments channel without removing the key-list API:

| Aspect | Rule |
| --- | --- |
| Method | `resolveRequests(List<Map<String, Object?>> requests)` where each entry is `{key, arguments}`. |
| `key` | Required string (`domain.concept@vN`). |
| `arguments` | Optional object (or null/empty). Passed through to the registered resolver function. |
| Capability id | Still **absent.** |
| Key-list wrapper | `resolve(keys)` MUST remain and MUST delegate with null/empty arguments. |

Registered resolver functions accept an optional `arguments` parameter. Existing E3 registrations
MAY ignore arguments (e.g. visit id constructor-injected on the port). New keys MAY use arguments
for request-scoped filters (patient hint, date range) per §6.7.2 / §8.10.

RLS “payloads — or nothing” is a **success** with empty/omitted values for a key, not
`ContextResolveFailure`. `resolution_failed` / `unknown_context_key` remain true failures.

---

## 3. Registration

Context key → resolver function bindings live in **one closed static map** in a single registration
module (`context_registration.dart`). E3 registers the first published key
`visit.chief_complaint@v1`. Later slices may add entries to the map; they must not change the
key-list API.

### 3.1 Per-visit ContextProviderPort construction

`ContextProviderPort.fetchVisitChiefComplaint()` takes **no arguments**. The clinic visit id is
**constructor-injected** on the production port (`SupabaseContextProviderPort(client:, visitId:)`).
Hosts build one port instance per screen/visit and pass it into `ContextResolver` /
`AiFeatureHostDependencies`. This keeps the frozen key-list API argument-free while still
supplying `p_visit_id` to `public.get_visit_chief_complaint`.

---

## 4. Screen-scoped cache

| Aspect | Rule |
| --- | --- |
| Ownership | One Resolver instance per screen; cache is **instance state**. |
| Lifetime | Short-lived results cached only while that instance lives. |
| Dispose | Disposing the screen/host discards the instance and its cache. |
| Cross-screen | No cross-screen or process-lifetime cache from this component. |

---

## 5. Must not

| Prohibition | Source |
| --- | --- |
| Decide which keys are needed | §4.1 Must not |
| Send unrequested or invented data | §4.1 Must not |
| Bypass RLS via a privileged path | §4.1 Must not |
| Accept or branch on capability id | §4.1; delivery plan §3.6 Done when |
| Embed prompt text, provider names, or model identifiers | R-12; FR-013 |

---

## 6. Client contract suite binding

The Flutter client contract suite (§13.5) consumes this API: for every active capability manifest
in C1 discovery shape (`specs/025-capability-resolver-discovery/contracts/capability-registry.md`),
every declared context key MUST be present in the registration map and resolve to a success whose
per-key value is a `Map` conforming to the key’s A5 shape (no undeclared fields). A manifest
requiring an unregistered key MUST fail the suite.

**Hermetic narrowing (documented):** the suite loads fixtures **derived from**
`ai-platform/manifests/published/*.json` (checked in under
`frontend/test/fixtures/ai/published_manifests_discovery.json`) and asserts those fixtures agree
with the published files (drift gate). It does **not** perform a live Worker discovery fetch in CI,
while still satisfying the drift-catching purpose of §13.5.
