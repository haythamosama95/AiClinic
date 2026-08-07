# Contract: Discovery HTTP wire (I2)

**Frozen by:** Slice I2 — Discovery HTTP route and production config-cache readers
**Implements:** §5.5, §4.3.4, §4.3.2 of `docs/architecture/ai-platform/01-ai-platform.md`
**Status:** Frozen. Later slices (I3) **consume** this artifact; they extend, never rewrite the
route path/method, Bearer AAT auth rule, conditional-revalidation headers, response body shape, or
`unauthenticated` failure mapping.

**Source of truth in code:** `ai-platform/src/discovery/index.ts` (HTTP handler) composing
`ai-platform/src/capability/index.ts` (`discover`, `buildDiscoveryResponse`) and
`ai-platform/src/identity/index.ts` (`EnrolledKeyVerifier`).

**Traces to:** FR-001..FR-006; spec Freezes → live capability-discovery HTTP wire; C1 library
contract (`specs/025-capability-resolver-discovery/contracts/capability-registry.md`).

---

## 1. Overview

I2 exposes C1's `discover()` over the live Worker fetch path. It does **not** redefine registry
filtering, etag computation, or `If-None-Match` matching — those remain C1's. This artifact freezes
only the HTTP mounting: path, auth, headers, success/error bodies, and the rule that the handler
shares one config cache/reader between AAT verification and `discover()` on the same request.

Production D1 config-cache readers (I2's second Freezes entry) bind to A5's config-cache contract
(`specs/019-ai-context-keys-d1-config/contracts/config-cache.md`) and are not re-specified here.

---

## 2. Route

| Field | Value |
| --- | --- |
| Method | `GET` |
| Path | `/v1/capabilities` |
| Capability id | **Never required** on the wire — the authenticated installation's entitlements and grants alone determine the returned set |

---

## 3. Authentication

| Rule | Detail |
| --- | --- |
| Header | `Authorization: Bearer <AAT>` |
| Scope | Installation-scoped |
| Verifier | Same enrolled-key verifier as submit (`EnrolledKeyVerifier` / §4.3.2 / §5.6) |
| Shared state | One `ConfigCache` + one `createD1ConfigReader` instance per request, passed to both `verify` and `discover()` |

### 3.1 Failure

Missing `Authorization`, non-Bearer scheme, empty token, or verifier failure → taxonomy
`unauthenticated`:

| Field | Value |
| --- | --- |
| HTTP status | `liveHttpStatusForCode("unauthenticated")` (401) |
| Body | Taxonomy error body (`buildErrorBody` with code `unauthenticated`) |
| Discovery body | **Absent** — no `{ manifests: … }` |

---

## 4. Success response

After successful verification the handler calls `discover(principal, cache, reader)` then
`buildDiscoveryResponse(request, manifests, etag)` (C1).

### 4.1 Body (HTTP 200)

```json
{ "manifests": [ /* Manifest[] — granted, effective active or deprecated */ ] }
```

Manifests follow C1's `DiscoveryResult` / immutability rules. Entitlement-gated capabilities for an
ineligible plan are **absent** from the array (not an error code on this surface).

### 4.2 Headers (HTTP 200 and 304)

| Header | Value |
| --- | --- |
| `ETag` | Quoted strong tag `"${rawHash}"` from C1 `computeDiscoveryEtag` |
| `Cache-Control` | `private, must-revalidate` |
| `Content-Type` | `application/json` on `200` only |

### 4.3 Conditional revalidation

| Condition | Response |
| --- | --- |
| `If-None-Match` matches prior `ETag` (C1 weak-comparison rules) | `304 Not Modified`, empty body |
| Mismatch or header absent | `200` with full discovery body; `ETag` reflects the current filtered set |

A changed granted-manifest set produces a different `ETag`.

---

## 5. Prohibitions on this surface

- No capability id query/path parameter required or interpreted as a filter input.
- No Quota Durable Object round trip.
- No R2 object.
- No journal row for auth failure.
- No per-request server-side state beyond the in-isolate config cache (A5).
- No re-implementation of C1 filtering or etag logic inside the handler.

---

## 6. Consumers

| Slice | How it binds |
| --- | --- |
| **I3** | Flutter live invoke composes discovery results fetched from this wire |
| Later client SDK / E-band surfaces | May call `GET /v1/capabilities` with Bearer AAT and honor `ETag` / `If-None-Match` |
