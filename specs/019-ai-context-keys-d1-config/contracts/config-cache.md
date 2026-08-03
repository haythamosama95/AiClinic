# Config cache contract (A5)

Frozen in-isolate config-cache contract: six cached entity kinds, short TTL, D1-on-miss I/O
budget, typed failure on a D1 miss, owns-nothing semantics, and in-isolate memory only (no KV).
Later slice **B3 (guard)** **consumes** this artifact — it reads installation keys, entitlements,
grants, kill switches, and routing policy through the cache with **no D1 read on a warm isolate**.

**Source of truth in code:** `ai-platform/src/config-cache/index.ts` (`ConfigEntityKind`,
`D1Reader`, `ConfigCache`, `loadConfig`, `ConfigCacheMissError`, `CACHE_TTL_MS`).

**Traces to:** spec FR-014–FR-019; architecture §4.3.2, §4.4, §9.15.

---

## 1. Overview

The config cache is **not a store**. It is a latency optimization over D1: an in-isolate memory map
with a short time-to-live (TTL), populated from D1 on a miss, holding copies of installation-scoped
configuration rows. D1 remains the only authoritative source of config truth (§4.4).

Clinic scale (tens of installations, a few kilobytes of config) makes the entire cached set fit
comfortably in isolate memory (§9.15). A warm isolate answers config consults in nanoseconds; a cold
isolate pays exactly one same-region D1 read per miss.

There is **no store for live request state** (§4.4, §9.7). The cache holds installation-scoped
copies only; no per-request handle or session object is introduced.

---

## 2. Cached entity kinds

The cache partitions entries by **entity kind**. Exactly six kinds are cached; no other kind is
supported in A5.

| Kind (`ConfigEntityKind`) | D1 source (§7.3) | Held data |
| --- | --- | --- |
| `installations` | `installation` | Installation record and status |
| `keys` | `installation_key` | Installation public keys |
| `entitlements` | `entitlement` | Plan entitlements for an installation |
| `grants` | `capability_grant` | Per-capability grants |
| `kill_switches` | control-plane kill-switch state | Per-capability, per-installation, and global kill switches |
| `active_routing_policy` | `routing_policy` | The active routing policy version |

Each kind has its own TTL map keyed by an installation-scoped lookup key (e.g.
`installation:<installation_id>`). A warm isolate MUST answer consults for **all six kinds** from
memory with no I/O (FR-016; test `T-A5-20`).

---

## 3. Storage model

### 3.1 In-isolate memory only

The cache MUST be an in-isolate `Map` per entity kind. Entries live in the Worker's isolate heap
for the lifetime of that isolate (or until TTL expiry evicts them).

### 3.2 No KV binding

Workers KV as a hot config cache is **rejected** (§9.15). The config-cache module exports no KV
surface, and `ai-platform/wrangler.toml` introduces no KV namespace binding for config (test
`T-A5-23`; FR-014).

### 3.3 Short TTL

Each cached entry carries an `expiresAt` timestamp. The TTL is a **plan-time constant**
(`CACHE_TTL_MS`, currently 30 seconds) within the architecture's "short TTL" constraint (§4.3.2).
It is **not** a runtime configuration surface (R-20).

On consult, an expired entry is deleted and treated as a miss, triggering a refetch (§4.3).

---

## 4. I/O budget

All I/O flows through the injected **`D1Reader`** port — a single `read(key)` seam whose call count
spy tests assert (Clarification Q3). The cache module does not import D1 bindings directly; callers
(or later slices) supply a reader that maps lookup keys to D1 rows.

### 4.1 Cold isolate — exactly one D1 read on miss

When `loadConfig` is called and the cache has no valid (non-expired) entry for the requested
`(kind, key)` pair, it MUST perform **exactly one** `reader.read(key)` and cache the returned row
(FR-017; test `T-A5-17`).

### 4.2 Warm isolate — zero I/O

When `loadConfig` is called and a valid cached entry exists, it MUST return from memory with **zero**
`reader.read` calls (FR-016; test `T-A5-18`).

### 4.3 TTL expiry — exactly one refetch

When a previously cached entry has expired, the next `loadConfig` consult MUST delete the stale entry,
perform **exactly one** `reader.read(key)`, and store the fresh row (FR-018; test `T-A5-19`).

Subsequent consults before the new TTL expires again perform zero reads.

---

## 5. D1 miss — typed failure

When `reader.read(key)` returns `"miss"` (the requested config row does not exist in D1),
`loadConfig` MUST:

1. Throw **`ConfigCacheMissError`** — a typed failure carrying `kind` and `key` (FR-019).
2. **Not** cache an empty or sentinel entry (negative caching is forbidden).

A follow-up consult after a miss, once D1 has the row, MUST still perform one `reader.read` because
nothing was stored on the failed attempt (test `T-A5-21`).

Callers (including B3 guard) MUST distinguish a config miss from a warm-cache hit or a successful
cold load. An unknown installation must not be confused with a cached absence.

---

## 6. Owns nothing

The cache is a read-through copy layer; it does **not** own config truth (FR-015; §4.4).

### 6.1 Returns copies

`consult` and `loadConfig` return **copies** of cached rows (`structuredClone`). Mutating a returned
object does not alter the cache or D1.

### 6.2 D1 updates propagate after TTL

When D1 changes underneath a cached entry, the new value becomes visible after TTL expiry without an
explicit cache flush — the next post-expiry consult refetches from D1 (test `T-A5-22`). There is no
cache invalidation API in A5; TTL is the only freshness mechanism.

### 6.3 No per-request state

The module exports only installation-scoped cache operations. No per-request handle, session store,
or request-scoped mutable state is introduced (test `T-A5-24`).

---

## 7. API surface

`ai-platform/src/config-cache/` exports:

| Export | Role |
| --- | --- |
| `ConfigEntityKind` | Closed union of the six cached kinds (§2). |
| `D1Reader` | Port: `read(key: string) => Promise<D1Row \| "miss">`. |
| `ConfigCache` | In-isolate TTL map; `consult(kind, key)` and `remember(kind, key, value)`. |
| `loadConfig(cache, reader, kind, key)` | Primary entry point: cache hit → copy; miss/expiry → one D1 read. |
| `ConfigCacheMissError` | Typed failure on D1 miss (§5). |
| `CACHE_TTL_MS` | Plan-time TTL constant (§3.3). |

`D1Row` is `Record<string, unknown>` — the cache is agnostic to row shape; entity-specific field
contracts live in `data-model.md` and the D1 schema.

---

## 8. Consumers

| Slice | Binding |
| --- | --- |
| **B3 (guard)** | Reads installations, keys, entitlements, grants, kill switches, and active routing policy through `loadConfig` on a shared `ConfigCache` instance. On a **warm isolate**, guard consults MUST incur **zero D1 reads** (FR-016). Identity verification, audience/expiry/skew, `jti` replay, and immutable request principal are B3 concerns — A5 freezes only the cache contract B3 reads through. |
| **B2 (enrollment)** | Writes the `installation`, `installation_key`, and `entitlement` rows that the cache later copies. B2 does not use the cache module. |

Later slices MUST **consume** this artifact. They extend wiring around the cache; they do not rewrite
the six kinds, I/O budget, miss semantics, or storage model.

---

## 9. Verification

Contract behaviour is enforced by `ai-platform/test/config-cache.test.ts`:

| Test | Asserts |
| --- | --- |
| `T-A5-17` | Cold isolate: exactly one `reader.read` on miss |
| `T-A5-18` | Warm isolate: zero `reader.read` |
| `T-A5-19` | TTL expiry: exactly one refetch |
| `T-A5-20` | All six entity kinds: warm zero I/O |
| `T-A5-21` | D1 miss: `ConfigCacheMissError`; no negative cache |
| `T-A5-22` | Owns nothing: D1 update visible after TTL |
| `T-A5-23` | In-isolate memory; no KV binding |
| `T-A5-24` | No per-request state on export surface |
