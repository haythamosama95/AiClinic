# Contract: Capability registry, resolver, and discovery (C1)

**Frozen by:** Slice C1 — Capability registry, resolver stage, and discovery endpoint
**Implements:** §4.3.4, §5.1, §6.1 stage 5, §5.5, §5.2 of `docs/architecture/17-ai-platform.md`
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
immutable manifest or a taxonomy error code. `discover()` returns the granted, `active`
manifest set for the caller's installation and plan, plus a stable etag for client caching.

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
| Success | `{ ok: true, manifest: Manifest }` | The pinned version exists, is not `retired`, and is not kill-switched. |
| Failure | `{ ok: false, code: <taxonomy code> }` | Resolution failed; see §4. |

The `code` field on failure is exactly one of:

| Code | Condition |
| --- | --- |
| `capability_unknown` | No registry entry for `capabilityId@version`. |
| `capability_retired` | Entry exists and `Identity.lifecycleState === "retired"`. |
| `capability_disabled` | Entry exists, is not `retired`, and any kill-switch scope is active (§4.3). |

No other failure codes are emitted by `resolve()`. Entitlement and plan-tier gating are
discovery-only filters; an ineligible installation that pins an existing version receives
`{ ok: true, manifest }` from `resolve()` (B3's `forbidden_capability` applies at stage 3, not
here).

---

## 4. Resolver behaviour

### 4.1 Exact version pin

Resolution honours the client's requested version literally. A request for `1.2.0` when only
`1.0.0` is registered returns `{ ok: false, code: "capability_unknown" }` — not a newer or
"nearest" version.

### 4.2 Lifecycle states

| `Identity.lifecycleState` | `resolve()` outcome |
| --- | --- |
| `active` | Served when not kill-switched. |
| `deprecated` | Served when not kill-switched (deprecation is not a rejection; overlap window is J1). |
| `retired` | `{ ok: false, code: "capability_retired" }`. |

### 4.3 Kill-switch evaluation

After registry lookup and the retired check, `resolve()` reads kill-switch rows via
`loadConfig(cache, reader, "kill_switches", …)` (B3 config-cache surface). The capability is
disabled when **any** of the following scopes has `active === true`:

| Scope key | Composition |
| --- | --- |
| `global` | Platform-wide kill switch. |
| `capability:<capabilityId>` | Capability-scoped kill switch. |
| `installation:<installationId>` | Installation-scoped kill switch (`principal.installationId`). |
| `provider:<providerId>` | Provider-scoped kill switch; `providerId` is resolved from the manifest's `Routing.routingPolicyRef` via `active_routing_policy` config. Omitted when the policy row is absent. |

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
| `manifests` | Granted, `active`-lifecycle manifests for the principal's installation, sorted by registry key ascending. |
| `etag` | Stable content hash of the granted+active set (§6). |

The HTTP response body produced by `buildDiscoveryResponse()` serialises only
`{ manifests: Manifest[] }`; the etag is carried on the `ETag` response header, not inside
the JSON body.

---

## 6. Discovery filtering

`discover()` enumerates the registry and includes a manifest only when **all** of the
following hold:

| Filter | Rule |
| --- | --- |
| Lifecycle | `Identity.lifecycleState === "active"` (`deprecated` and `retired` are excluded). |
| Entitlement status | Installation entitlement row exists with `status === "active"`. |
| Allowed capabilities | `capabilityId` is listed in entitlement `allowed_capabilities`. |
| Plan tier | Entitlement `plan` meets or exceeds `Access.minimumPlanTier` (ordered: `starter` < `standard` < `professional` < `enterprise`). |
| Grant | A `grants` row for `${installationId}/${capabilityId}` exists and `revoked_at` is null. |

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
   `hashManifest()` — canonical encoding (sorted object keys, recursive; FNV-1a 32-bit,
   hex-padded to 8 characters). No separate hashing mechanism is introduced (R-20).

Any change to the granted+active set — adding or removing a manifest, or changing any field
group on a member manifest — produces a different etag.

---

## 8. Conditional discovery response

`buildDiscoveryResponse(request, manifestList, etag)` implements §5.2 revalidation:

| Condition | Response |
| --- | --- |
| `request.headers.get("If-None-Match") === etag` | `304 Not Modified`, empty body, `ETag` header set to `etag`. The manifest list is **not** re-serialised. |
| Otherwise | `200 OK`, JSON body `{ manifests: manifestList }`, headers `ETag: <etag>` and `Content-Type: application/json`. |

The comparison is a strict string equality on the full etag value.

---

## 9. Resolved-manifest immutability

Manifests enter the registry through `createCapabilityRegistry()`, which applies `deepFreeze`
to every field group (including each `Context requirements` entry) before insertion. A4's
`Proxy`-based freeze from `load()` is therefore reinforced at the registry boundary.

`resolve()` returns the registry's frozen `Manifest` reference — not a copy. A caller that
attempts to mutate any field group or reassign a top-level group key has no observable effect
on what subsequent readers see (`T-C1-06 resolver_manifest_immutable`). No `withManifest` or
other mutator is exported.

Later stages (C2 context validator, D1 prompt composer) must treat the resolved manifest as
read-only for the lifetime of the request.

---

## 10. Export surface

`ai-platform/src/capability/` exports:

| Export | Role |
| --- | --- |
| `CapabilityRegistry` | `Map<string, Manifest>` type alias. |
| `ResolveResult` | Discriminated union for resolver outcomes. |
| `DiscoveryResult` | Discovery payload type (`manifests` + `etag`). |
| `createCapabilityRegistry(manifests)` | Build a frozen registry from loaded manifests. |
| `setCapabilityRegistry(registry)` | Install the process-wide registry (test and bootstrap hook). |
| `resolve(…)` | Pipeline stage-5 resolver. |
| `discover(…)` | Installation-scoped discovery enumeration. |
| `computeDiscoveryEtag(manifestList)` | Etag helper (shared by `discover` and contract tests). |
| `buildDiscoveryResponse(request, manifestList, etag)` | HTTP response builder with conditional `304`. |

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
| Entitlement rejection at submit (`forbidden_capability`) | B3 | Stage 3; not a resolver error code. |
| HTTP status mapping for taxonomy codes | A6 | C1 emits codes only. |
| Deprecation overlap window | J1 | `deprecated` manifests are served by `resolve()` and excluded from `discover()`. |
| Live Worker route wiring | Later slice | C1 exposes library functions; `worker.ts` is not modified in this slice. |
