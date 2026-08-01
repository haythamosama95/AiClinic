# Quickstart: First real provider adapter (D5)

Slice D5 adds the first real provider adapter — DeepSeek behind the D2 provider port — with recorded-fixture proof for wire mapping, stream normalization, usage extraction, error classification, and secret-store credentials that never appear in logs or journal records. The permanent suite uses injectable transport; no live provider egress.

**Scope rule:** This quickstart documents **this slice only**. It lists only files D5 added or modified, only D5 test files, and only commands that run D5 tests.

## 1. Architecture context

- **Delivery plan row D5** ([`../../docs/architecture/17b-ai-platform-delivery-plan.md`](../../docs/architecture/17b-ai-platform-delivery-plan.md) §3.5): first real provider adapter in band D — wire mapping, stream normalization, usage extraction, error classification, and secret-store credentials proven by recorded fixtures.
- **Architecture section implemented** ([`../../docs/architecture/17-ai-platform.md`](../../docs/architecture/17-ai-platform.md)):
  - §4.3.8 — provider adapters and egress (first real adapter behind the D2 port; owns auth, mapping, normalization, timeouts, and retryable/terminal classification; owns no retry, fallback, or logging policy)
- **Spec delivered** ([`spec.md`](spec.md)): frozen first real provider adapter duties, recorded-fixture adapter suite shape (T1–T11), and secret-store credential path with absence spy; exactly one provider (`deepseek`) in this slice.
- **Plan scoped** ([`plan.md`](plan.md)): `DeepSeekAdapter` in `ai-platform/src/provider/deepseek.ts`; recorded fixtures under `ai-platform/test/fixtures/deepseek/`; adapter-fixture suite in `ai-platform/test/deepseek-adapter.test.ts`; frozen contract in `contracts/first-real-provider-adapter.md`; no D1 migrations, no `wrangler.toml` changes, no pipeline registration.

## 2. What was implemented

- `ai-platform/src/provider/deepseek.ts` — `DeepSeekAdapter` implements D2 `ProviderPort`; injectable transport and secret-store ports; owns auth, wire mapping, stream normalization, usage extraction, timeouts, and failure classification; export surface exposes no retry, fallback, or logging-policy API.
- `ai-platform/test/fixtures/deepseek/` — recorded request/response and stream pairs for wire golden, stream, usage, error classes, malformed, truncated, and timeout cases.
- `ai-platform/test/deepseek-adapter.test.ts` — eleven named adapter-fixture tests (T1–T11) including credential-absence and secret-store spies.
- Frozen contract: [`contracts/first-real-provider-adapter.md`](contracts/first-real-provider-adapter.md) — adapter duties, fixture suite shape D7 must mirror, secret-store credential path.

See [`spec.md`](spec.md) for full requirements and [`plan.md`](plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/provider/deepseek.ts` | `DeepSeekAdapter` — real provider behind `ProviderPort` |
| `ai-platform/test/deepseek-adapter.test.ts` | T-D5-01..11 adapter-fixture and spy tests (14 cases) |
| `ai-platform/test/fixtures/deepseek/` | Recorded wire, stream, usage, error, malformed, truncated, and timeout fixtures |
| `specs/032-first-real-provider-adapter/contracts/first-real-provider-adapter.md` | Frozen adapter duties, fixture suite shape, secret-store path |

## 4. Prerequisites

From the repository root, first time only:

```bash
cd ai-platform
npm install
```

D5 tests are CPU-only — no Miniflare bindings, Cloudflare resources, or live DeepSeek API calls are required for this slice's suite.

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run test/deepseek-adapter.test.ts
```

Expected: **14 passing tests** for this slice only (`deepseek-adapter.test.ts` — eleven named cases; T4 expands to four error-class subcases).

To run a subset by named case:

```bash
npx vitest run test/deepseek-adapter.test.ts -t "request_mapping_golden"
```

## 6. Inspect the changes

Read the frozen contract:

```bash
cat specs/032-first-real-provider-adapter/contracts/first-real-provider-adapter.md
```

Open the adapter module:

```bash
less ai-platform/src/provider/deepseek.ts
```

Run the focused test file:

```bash
cd ai-platform
npx vitest run test/deepseek-adapter.test.ts
```
