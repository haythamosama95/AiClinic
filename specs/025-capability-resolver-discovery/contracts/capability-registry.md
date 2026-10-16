# Contract: Capability registry, resolver, and discovery (C1)

**Frozen by:** Slice C1 — Capability registry, resolver stage, and discovery endpoint
**Implements:** §4.3.4, §5.1, §6.1 stage 5, §5.5, §5.2 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices (C2, D1, E3) **consume** this artifact; they extend, never rewrite
the `ResolveResult` union, the `DiscoveryResult` shape, the registry key format, the etag
computation, the `If-None-Match` → `304` rule, or the resolved-manifest immutability guarantee.

**Source of truth in code:** `ai-platform/src/capability/index.ts` (`CapabilityRegistry`,
`ResolveResult`, `DiscoveryResult`, `resolve`, `discover`, `computeDiscoveryEtag`,
`buildDiscoveryResponse`).

**Traces to:** FR-001, FR-008, FR-013; spec Freezes entries; A4 manifest wire shape
(`specs/018-ai-capability-manifest/contracts/manifest-schema.md`); B3 request principal
(`specs/023-guard-stages/contracts/request-principal.md`).

---

## 1. Overview

C1 owns the in-memory **capability registry** (a map from registry keys to A4 manifests),
the pipeline **resolver** stage (§6.1 stage 5), and the **discovery** surface (§5.5, §5.2).
A submit request supplies a capability id and an exact version pin; `resolve()` returns one
immutable manifest or a taxonomy error code. `discover()` returns the granted manifests whose
effective lifecycle is `active` or `deprecated` for the caller's installation and plan, plus a
stable etag for client caching.

The module does not re-implement manifest validation (A4's `load()` owns that) and does not
translate taxonomy codes to HTTP statuses (A6 owns that). It emits codes and wire shapes only.

---

## 2. Registry key format

The registry is a `Map` whose keys are strings in the form:

```
<capabilityId>@<version>
```

Example: `clinic.visit_summary@1.0.0`

`createCapabilityRegistry(manifests)` builds the map from A4-loaded manifests, using each
manifest's `Identity.capabilityId` and `Identity.version`. Lookup is exact: there is no
"compatible version" fallback and no semver range resolution (§4.3.4).

---

## 3. ResolveResult

`resolve(principal, capabilityId, version, cache, reader)` returns a discriminated union:

| Branch | Shape | Meaning |
| --- | --- | --- |
| Success | `{ ok: true, manifest: Manifest }` | The pinned version exists, is not effectively `retired`, passes plan-level allowance and grant-version checks, and is not kill-switched. |
| Failure | `{ ok: false, code: <taxonomy code> }` | Resolution failed; see §4. |

The `code` field on failure is exactly one of:

| Code | Condition |
| --- | --- |
| `capability_unknown` | No registry entry for `capabilityId@version`. |
| `capability_retired` | Entry exists and effective lifecycle is `retired` (§4.2, §5.1). |
| `forbidden_capability` | Entry exists and is not effectively `retired`, but the installation fails plan-level allowance or grant-version match (§4.3). |
| `capability_disabled` | Entry exists, is not effectively `retired`, passes allowance/grant, and any kill-switch scope is active (§4.4). |

No other failure codes are emitted by `resolve()`. Plan-level allowances and grant-version
match are enforced in `resolve()` (fail closed with `forbidden_capability`); B3's stage 3
still owns entitlement rejection on the submit path, and `resolve()` also fails closed on the
same class of allowance/grant failures.

---

## 4. Resolver behaviour

Evaluation order: **lookup → retired (effective lifecycle via overlay) → allowance/grant →
kill switches**.

### 4.1 Exact version pin

Resolution honours the client's requested version literally. A request for `1.2.0` when only
`1.0.0` is registered returns `{ ok: false, code: "capability_unknown" }` — not a newer or
"nearest" version.

### 4.2 Lifecycle states

Effective lifecycle is derived from the published `Identity` overridden by a lifecycle overlay
when present (§5.1). `resolve()` uses that effective state:

| Effective `lifecycleState` | `resolve()` outcome |
| --- | --- |
| `active` | Continues to allowance/grant and kill-switch checks. |
| `deprecated` | Continues (deprecation is not a rejection; overlap window is J1). |
| `retired` | `{ ok: false, code: "capability_retired" }`. |

### 4.3 Plan-level allowance and grant-version check

After the retired check and before kill switches, `resolve()` enforces plan-level allowances
and grant version match for the principal's installation:

| Check | Rule | Failure |
| --- | --- | --- |
| Entitlement / plan | Installation entitlement is active and its `plan` meets or exceeds the manifest's `Access.minimumPlanTier`; `capabilityId` is listed in `allowed_capabilities`. Malformed `allowed_capabilities` fails closed. | `forbidden_capability` |
| Grant presence | An installation grant `${installationId}/${capabilityId}` is tried first; on miss, a plan grant `plan:${plan}/${capabilityId}` is accepted (same B3 semantics). Revoked → reject. | `forbidden_capability` |
| Grant version | When `capability_version` on the matched grant is a string, it must equal the requested (pinned) version. | `forbidden_capability` |

Helper `getGrantedCapabilityVersion(installationId, capabilityId, cache, reader)` returns the
grant's `capability_version` string, or `null` when the grant is missing, revoked, or has no
string version.

### 4.4 Kill-switch evaluation

After registry lookup, the retired check, and the allowance/grant check, `resolve()` reads
kill-switch rows via `loadConfig(cache, reader, "kill_switches", …)` (B3 config-cache
surface). A **miss** (`ConfigCacheMissError`) is treated as `{ active: false }` / inactive —
absent means inactive. The capability is disabled when **any** of the following scopes has
`active === true`:

| Scope key | Composition |
| --- | --- |
| `global` | Platform-wide kill switch. |
| `capability:<capabilityId>` | Capability-scoped kill switch. |
| `installation:<installationId>` | Installation-scoped kill switch (`principal.installationId`). |
| `provider:<providerId>` | Provider-scoped kill switch; `providerId` is resolved from the manifest's `Routing.routingPolicyRef` via `active_routing_policy` config. **Omitted** when the policy row is absent (miss) or when `routingPolicyRef` is not a string. |

When any scope is active, `resolve()` returns `{ ok: false, code: "capability_disabled" }`.

---

## 5. DiscoveryResult

`discover(principal, cache, reader)` returns:

```typescript
{
  manifests: Manifest[];
  etag: string;
}
```

| Field | Contents |
| --- | --- |
| `manifests` | Granted manifests whose effective lifecycle is `active` or `deprecated` for the principal's installation, sorted by registry key ascending. When the overlay or published `Identity` provides a successor, the returned (possibly derived) manifest carries that successor identity. |
| `etag` | Stable content hash of the filtered discovery set after effective-identity derivation (§6, §7). |

The HTTP response body produced by `buildDiscoveryResponse()` serialises only
`{ manifests: Manifest[] }`; the etag is carried on the `ETag` response header, not inside
the JSON body.

### 5.1 Lifecycle overlay and effective identity

A lifecycle overlay may be loaded from the config cache at
`grants` / `global/<capabilityId>/<version>`. When present, overlay fields override the
published manifest `Identity` for effective lifecycle and successor (architecture §5.1):

| Type / helper | Role |
| --- | --- |
| `LifecycleOverlay` | Overlay row shape (`lifecycle_state`, `successor_id`, optional timestamps). |
| `EffectiveLifecycle` | `{ lifecycleState, successorId }` after overlay wins over published Identity. |
| `effectiveLifecycle(manifest, overlay)` | Pure derivation; overlay `lifecycle_state` wins when set; successor falls back to published when overlay omits it. |

When effective Identity differs from the published registry entry, `resolve()` / `discover()`
return a derived, deep-frozen manifest copy with the effective `Identity` fields — the
registry's published bytes remain untouched.

---

## 6. Discovery filtering

`discover()` enumerates the registry and includes a manifest only when **all** of the
following hold:

| Filter | Rule |
| --- | --- |
| Lifecycle | Effective lifecycle ∈ `{ active, deprecated }` (overlay wins over published Identity per §5.1). Effectively `retired` is excluded. |
| Entitlement status | Installation entitlement row exists with `status === "active"`. |
| Allowed capabilities | `capabilityId` is listed in entitlement `allowed_capabilities`. |
| Plan tier | Entitlement `plan` meets or exceeds `Access.minimumPlanTier` (ordered: `starter` < `standard` < `professional` < `enterprise`). |
| Grant | A `grants` row for `${installationId}/${capabilityId}` exists, `revoked_at` is null, **and** when `capability_version` is a string it must equal the manifest version. |

Kill switches are **not** applied to discovery: a killed capability may still be advertised.
The discovery etag does **not** change on a kill-switch flip alone.

Capabilities that fail any filter are **absent** from the result — not emitted as errors.
When entitlement is missing, inactive, or has no plan, `discover()` returns an empty
`manifests` array and an etag computed over that empty set.

---

## 7. Etag computation

`computeDiscoveryEtag(manifestList)` derives the etag as follows:

1. **Sort** manifests by registry key (`${capabilityId}@${version}`) using locale-aware string
   comparison.
2. **Serialise** each manifest into a hash input object containing all ten A4 field groups
   (group names verbatim, including spaces):
   - `Identity`, `Access`, `Interaction`, `Input`, `Context requirements`, `Prompt binding`,
     `Output`, `Routing`, `Economics`, `Governance`.
3. **Hash** the wrapper object `{ manifests: [<hash inputs in sorted order>] }` with A4's
   `hashManifest()` — canonical encoding (sorted object keys, recursive; **SHA-256**, hex
   digest). No separate hashing mechanism is introduced (R-20).

The input list is the **filtered discovery set after effective-identity derivation**
(overlay-derived manifests when Identity changed) — not raw published-only registry entries.
Any change to that set — adding or removing a manifest, or changing any field group on a
member (including overlay-driven Identity flips) — produces a different etag. Kill-switch
flips alone do not.

---

## 8. Conditional discovery response

`buildDiscoveryResponse(request, manifestList, etag)` implements §5.2 revalidation.

**Wire ETag.** The value returned by `computeDiscoveryEtag` is the raw hash. On the wire the
`ETag` header is the quoted strong tag `"${rawHash}"` (e.g. `ETag: "9f3a…"`).

**`If-None-Match` matching:**

| Condition | Response |
| --- | --- |
| Header absent | `200 OK` with body. |
| Header is `*` | `304 Not Modified`, empty body (no re-serialisation). |
| Comma-separated list | Weak comparison: optional `W/` prefix stripped; surrounding quotes stripped per tag; match if any list member equals the raw hash (bare unquoted raw hash also accepted). On match → `304`; otherwise `200`. |

**Headers on both 200 and 304:**

| Header | Value |
| --- | --- |
| `ETag` | `"${rawHash}"` (quoted strong tag) |
| `Cache-Control` | `private, must-revalidate` |
| `Content-Type` | `application/json` on `200` only |

A `304` does **not** re-serialise the manifest list (empty body). A `200` returns JSON body
`{ manifests: manifestList }`.

---

## 9. Resolved-manifest immutability

`createCapabilityRegistry(manifests)` deep-freezes every field group of each manifest
(including each `Context requirements` entry) before insertion, and returns an
**unmodifiable** `Map` facade: `set` / `delete` / `clear` throw. A4's `Proxy`-based freeze
from `load()` is therefore reinforced at the registry boundary.

`resolve()` returns either the registry's frozen `Manifest` reference (when effective
Identity matches published) **or** a derived deep-frozen copy when a lifecycle overlay
changes Identity (§5.1). A caller that attempts to mutate any field group or reassign a
top-level group key has no observable effect on what subsequent readers see
(`T-C1-06 resolver_manifest_immutable`). No `withManifest` or other mutator is exported.

`setCapabilityRegistry(registry)` is **install-once**: a second call without options throws.
Replacing the process-wide registry requires `{ replace: true }`
(`setCapabilityRegistry(registry, { replace: true })`).

Later stages (C2 context validator, D1 prompt composer) must treat the resolved manifest as
read-only for the lifetime of the request. Discovery callers likewise receive frozen
manifests (registry references or derived frozen copies).

---

## 10. Export surface

`ai-platform/src/capability/` exports:

| Export | Role |
| --- | --- |
| `CapabilityRegistry` | `Map<string, Manifest>` type alias. |
| `ResolveResult` | Discriminated union for resolver outcomes. |
| `DiscoveryResult` | Discovery payload type (`manifests` + `etag`). |
| `LifecycleOverlay` | Overlay row type for effective lifecycle derivation. |
| `EffectiveLifecycle` | Effective `{ lifecycleState, successorId }` type. |
| `OVERLAP_WINDOW_MS` | OD-9 overlap window constant (two client release cycles, minimum 90 days — not a configuration surface). |
| `effectiveLifecycle(manifest, overlay)` | Pure effective-lifecycle derivation (§5.1). |
| `getGrantedCapabilityVersion(…)` | Grant `capability_version` helper (or `null`). |
| `createCapabilityRegistry(manifests)` | Build a frozen, unmodifiable registry from loaded manifests. |
| `setCapabilityRegistry(registry, options?)` | Install the process-wide registry (install-once; `{ replace: true }` to replace). |
| `resolve(…)` | Pipeline stage-5 resolver. |
| `discover(…)` | Installation-scoped discovery enumeration. |
| `computeDiscoveryEtag(manifestList)` | Etag helper (shared by `discover` and contract tests); returns the raw hash. |
| `buildDiscoveryResponse(request, manifestList, etag)` | HTTP response builder with conditional `304`, quoted `ETag`, and `Cache-Control`. |

Kill-switch scope evaluation and plan-tier comparison are internal; they are not exported.

---

## 11. Consumers

| Slice / stage | What it reads |
| --- | --- |
| **Context validator (C2)** | `ResolveResult.manifest` — all ten field groups, especially `Context requirements`. |
| **Prompt composer (D1)** | `ResolveResult.manifest` — `Prompt binding`, `Interaction`, `Output`. |
| **Client contract test (E3)** | `DiscoveryResult` wire shape, etag stability, `If-None-Match` → `304`. |
| **Protocol adapter (A6)** | Taxonomy codes from `ResolveResult.code` — maps to HTTP statuses; does not consume the manifest. |

---

## 12. Out of scope for this contract

| Behaviour | Owner | Reason |
| --- | --- | --- |
| Manifest schema and `load()` validation | A4 | Ten field groups, never-names-provider/model rule, published-version hash registry. |
| Stage-3 entitlement rejection (`forbidden_capability`) | B3 | Stage 3 still owns submit-path entitlement; `resolve()` also fails closed with the same code for allowance/grant failures (§4.3). |
| HTTP status mapping for taxonomy codes | A6 | C1 emits codes only. |
| Deprecation overlap window | J1 | Effectively `deprecated` manifests are served by `resolve()` and may appear in discovery with successor identity when overlay/published provides it; the overlap window itself remains J1. |
| Live Worker route wiring | Later slice | C1 exposes library functions; `worker.ts` is not modified in this slice. |
