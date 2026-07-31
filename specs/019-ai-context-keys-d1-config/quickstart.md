# Quickstart: Context key vocabulary, D1 schema, and config cache (A5)

Slice **A5** freezes three foundational gateway surfaces: the `domain.concept@vN` context-key
vocabulary with the first published shape, forward-only D1 migrations for every §7.3 entity, and an
in-isolate config cache that answers guard consults from memory when warm and from exactly one D1
read when cold.

Full requirements: [`spec.md`](spec.md). File-level traceability: [`plan.md`](plan.md).

## 1. Architecture context

This slice implements delivery-plan row **A5** (*Context key vocabulary, D1 schema, and config cache*),
which maps to §5.2, §7.3, §13.4, §4.3.2, §4.4, and §9.15 of
[`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md) and row A5 of
[`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md).

- The **spec** freezes the context-key naming and shape contract (`domain.concept@vN`, storage-named
  rejection, published field names/types/cardinality/units), the platform's D1 logical model (every
  §7.3 entity, unique request-reference index, nullable `conversation_id` / `turn_ordinal`), and the
  config-cache contract (six cached entity kinds, short TTL, warm zero I/O, cold one D1 read, typed
  failure on miss, owns-nothing, in-isolate-not-KV).
- The **plan** scopes three implementation units — `src/context/`, `src/config-cache/`, and
  `migrations/` plus `schema.snap.sql` — with twenty-four named contract/migration/spy tests
  (T-A5-01..24) across three test files. No request-path work; contracts and schema only.

## 2. What was implemented

- **Context-key vocabulary and first shape** — `ai-platform/src/context/index.ts` enforces
  `domain.concept@vN` format, rejects storage-named keys, publishes `visit.chief_complaint@v1` with its
  `KeyShape`, and exposes `validateKey()` / `validatePayload()` for contract-time validation.
- **D1 schema migrations** — `ai-platform/migrations/20260731120000_platform_schema.sql` creates
  every §7.3 entity with key fields, a unique request-reference index on `ai_request` (A2 format
  unchanged), and nullable `conversation_id` / `turn_ordinal` columns. The checked-in
  `ai-platform/schema.snap.sql` pins the post-migration DDL.
- **In-isolate config cache** — `ai-platform/src/config-cache/index.ts` defines the `D1Reader` port,
  `ConfigCache` with short TTL, and `loadConfig()` with the warm/cold/TTL I/O budget and typed failure
  on D1 miss. No KV binding; installation-scoped copies only.
- **Contract and data-model artifacts** — `contracts/context-key-schema.md`,
  `contracts/config-cache.md`, and `data-model.md` freeze the wire shapes and D1 logical model for
  later slices' Consumes review.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/context/index.ts` | Key format check, storage-named rejection, first published `KeyShape`, `validateKey` / `validatePayload` |
| `ai-platform/src/config-cache/index.ts` | `D1Reader` port, `ConfigCache`, `loadConfig`, TTL and miss behaviour |
| `ai-platform/migrations/20260731120000_platform_schema.sql` | Forward-only migration creating every §7.3 entity |
| `ai-platform/schema.snap.sql` | Checked-in DDL snapshot compared by `schema_snapshot_matches` |
| `ai-platform/test/context.test.ts` | T-A5-01..10 context-key contract suite |
| `ai-platform/test/migrations.test.ts` | T-A5-11..16 migration and schema-snapshot suite |
| `ai-platform/test/config-cache.test.ts` | T-A5-17..24 config-cache spy suite |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npm install   # first time only
npx vitest run test/context.test.ts test/migrations.test.ts test/config-cache.test.ts
```

Expected: **46 passing tests** across this slice's three test files — seventeen context-key cases
(T-A5-01..10), sixteen migration cases (T-A5-11..16), and thirteen config-cache cases (T-A5-17..24).

To run a single test file:

```bash
npx vitest run test/context.test.ts
npx vitest run test/migrations.test.ts
npx vitest run test/config-cache.test.ts
```

## 5. Inspect the changes

List applied D1 migrations (local Miniflare database):

```bash
cd ai-platform
npx wrangler d1 migrations list ai-platform-development --local
```

Read the pinned schema DDL:

```bash
cat ai-platform/schema.snap.sql
```

Read the frozen contract and data-model artifacts:

```bash
cat specs/019-ai-context-keys-d1-config/contracts/context-key-schema.md
cat specs/019-ai-context-keys-d1-config/contracts/config-cache.md
cat specs/019-ai-context-keys-d1-config/data-model.md
```

Inspect the first published context key and its shape in code:

```bash
grep -n 'VISIT_CHIEF_COMPLAINT_V1\|validateKey\|validatePayload' \
  ai-platform/src/context/index.ts
```

Inspect the config-cache I/O seam:

```bash
grep -n 'D1Reader\|loadConfig\|CACHE_TTL_MS\|ConfigCacheMissError' \
  ai-platform/src/config-cache/index.ts
```
