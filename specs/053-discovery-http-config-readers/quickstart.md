# Quickstart: Discovery HTTP route and production config-cache readers (I2)

I2 mounts C1's `discover()` on the live `GET /v1/capabilities` wire with Bearer AAT authentication,
ETag revalidation, and completes the production D1 config reader for every request-path kind —
including kill switches and `token_contract`.

**Scope rule:** This quickstart documents **this slice only**.

## 1. Architecture context

I2 implements the **I2** row in
[`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md)
§3.10, covering architecture sections **§5.5** (discovery HTTP wire), **§4.3.4** (capability
resolver composition), **§4.3.2** (production config-cache readers), and **§13.4**
(`token_contract` in the config-cache set).

- **What the spec delivered** ([`spec.md`](./spec.md)): live `GET /v1/capabilities` with Bearer AAT,
  conditional `If-None-Match` / `ETag` revalidation, and production D1 readers for every
  request-path config kind under A5's single cold-isolate read pattern.
- **What the plan scoped** ([`plan.md`](./plan.md)): discovery handler module, worker route,
  `kill_switch` migration + schema snapshot, `createD1ConfigReader` kill_switches SELECT, two
  Workers integration test files, and frozen `contracts/discovery-http.md`.

## 2. What was implemented

- **`GET /v1/capabilities`** — discovery HTTP handler sharing one `ConfigCache` + `createD1ConfigReader`
  between AAT verification and C1 `discover()` / `buildDiscoveryResponse`.
- **`createD1ConfigReader` kill_switches SELECT** — reads durable `kill_switch` rows; miss remains
  typed `ConfigCacheMissError`.
- **`kill_switch` migration + `schema.snap.sql`** — additive D1 table per §7.3.
- **Frozen contract** — [`contracts/discovery-http.md`](./contracts/discovery-http.md) for I3 to
  consume.

See [`spec.md`](./spec.md) for full requirements and [`plan.md`](./plan.md) for file-level
traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/discovery/index.ts` | HTTP handler: verify → `discover()` → `buildDiscoveryResponse` |
| `ai-platform/src/config-cache/index.ts` | Production `kill_switches` SELECT in `createD1ConfigReader` |
| `ai-platform/src/worker.ts` | Routes `GET /v1/capabilities` |
| `ai-platform/migrations/20260807120000_kill_switch.sql` | Additive `kill_switch` table |
| `ai-platform/schema.snap.sql` | Post-migration DDL snapshot |
| `ai-platform/test/discovery-http.test.ts` | T1–T5 discovery HTTP integration |
| `ai-platform/test/config-readers.test.ts` | T6–T14 production reader integration |
| `specs/053-discovery-http-config-readers/contracts/discovery-http.md` | Frozen discovery HTTP wire |

## 4. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run --config vitest.workers.config.ts test/discovery-http.test.ts test/config-readers.test.ts
```

Expected: **14 passing tests** for this slice only (T1–T14).

## 5. Inspect the changes

Confirm the worker route:

```bash
cd ai-platform
grep -n '/v1/capabilities' src/worker.ts src/discovery/index.ts
```

Read the frozen contract:

```bash
cat ../specs/053-discovery-http-config-readers/contracts/discovery-http.md
```

Confirm the kill_switches SELECT:

```bash
grep -n 'kill_switch' src/config-cache/index.ts
```

## 6. Manual validation

Optional local Worker check after `npm run dev`:

```bash
curl -sS -H "Authorization: Bearer <AAT>" \
  http://localhost:8787/v1/capabilities

curl -sS -H "Authorization: Bearer <AAT>" \
  -H 'If-None-Match: "<etag-from-prior-response>"' \
  -D - -o /dev/null \
  http://localhost:8787/v1/capabilities
```

A matching `If-None-Match` should return `304 Not Modified` with
`Cache-Control: private, must-revalidate`.
