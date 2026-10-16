# Quickstart: Second provider adapter (D7)

Slice D7 adds the second real provider adapter — Gemini behind the D2 provider port — with the same recorded-fixture suite shape as D5, secret-store credentials that never appear in logs or journal records, and routing-policy registration as a low-priority fallback with no inference-pipeline change. Capability-eval acceptance (FR-010 / T12 / SC-005) is deferred to F1.

**Scope rule:** This quickstart documents **this slice only**. It lists only files D7 added or modified, only D7 test files, and only commands that run D7 tests.

## 1. Architecture context

- **Delivery plan row D7** ([`../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md`](../../docs/architecture/ai-platform/03-ai-platform-delivery-plan.md) §3.5): second real provider adapter in band D — wire mapping, stream normalization, usage extraction, error classification, secret-store credentials, and policy-data fallback registration proven by recorded fixtures.
- **Architecture section implemented** ([`../../docs/architecture/ai-platform/01-ai-platform.md`](../../docs/architecture/ai-platform/01-ai-platform.md)):
  - §4.3.8 — provider adapters and egress (second real adapter behind the D2 port; owns auth, mapping, normalization, timeouts, and retryable/terminal classification; owns no retry, fallback, or logging policy)
  - §13.5 — provider adapter tests (recorded provider fixtures)
- **Spec delivered** ([`spec.md`](spec.md)): frozen Gemini adapter duties, D5 suite shape applied to the second provider, secret-store credential path, routing-policy low-priority registration with structural path allowlist; FR-010 / T12 deferred to F1.
- **Plan scoped** ([`plan.md`](plan.md)): `GeminiAdapter` in `ai-platform/src/provider/gemini.ts`; thin wiring map in `wiring.ts`; policy data in `control/routing-policy/platform-default/1.json`; recorded fixtures under `test/fixtures/gemini/`; adapter and policy tests; frozen contract in `contracts/second-provider-adapter.md`; no D1 migrations, no pipeline module changes.

## 2. What was implemented

- `ai-platform/src/provider/gemini.ts` — `GeminiAdapter` implements D2 `ProviderPort`; injectable transport and secret-store ports; owns auth, wire mapping, stream normalization, usage extraction, timeouts, and failure classification; export surface exposes no retry, fallback, or logging-policy API.
- `ai-platform/src/provider/wiring.ts` — thin `provider_id` → adapter construction map for DeepSeek and Gemini.
- `ai-platform/control/routing-policy/platform-default/1.json` — versioned routing-policy document listing Gemini as low-priority fallback after DeepSeek.
- `ai-platform/test/fixtures/gemini/` — recorded request/response and stream pairs for wire golden, stream, usage, error classes, malformed, truncated, and timeout cases.
- `ai-platform/test/gemini-adapter.test.ts` — eleven named adapter-fixture tests (T1–T11) including credential-absence and secret-store spies.
- `ai-platform/test/second-provider-policy.test.ts` — structural allowlist (T13) and fallback ordering (T14) tests.
- Frozen contract: [`contracts/second-provider-adapter.md`](contracts/second-provider-adapter.md) — Gemini adapter duties, D5 suite shape, secret-store path, policy registration proof.

Capability-eval acceptance (FR-010 / T12 / SC-005) is **deferred to F1** — not implemented in this slice.

See [`spec.md`](spec.md) for full requirements and [`plan.md`](plan.md) for file-level traceability.

## 3. Files to review

| Path | Role |
| --- | --- |
| `ai-platform/src/provider/gemini.ts` | `GeminiAdapter` — second real provider behind `ProviderPort` |
| `ai-platform/src/provider/wiring.ts` | Thin `provider_id` → adapter wiring map |
| `ai-platform/control/routing-policy/platform-default/1.json` | Routing-policy data with Gemini as low-priority fallback |
| `ai-platform/test/gemini-adapter.test.ts` | T-D7-01..11 adapter-fixture and spy tests (14 cases) |
| `ai-platform/test/second-provider-policy.test.ts` | T-D7-13 structural allowlist + T-D7-14 fallback ordering |
| `ai-platform/test/fixtures/gemini/` | Recorded wire, stream, usage, error, malformed, truncated, and timeout fixtures |
| `specs/034-second-provider-adapter/contracts/second-provider-adapter.md` | Frozen adapter duties, fixture suite shape, secret-store path, policy registration |

## 4. Prerequisites

From the repository root, first time only:

```bash
cd ai-platform
npm install
```

D7 tests are CPU-only — no Miniflare bindings, Cloudflare resources, or live Gemini API calls are required for this slice's suite.

## 5. Run the automated suite

From the repository root:

```bash
cd ai-platform
npx vitest run test/gemini-adapter.test.ts test/second-provider-policy.test.ts
```

Expected: **16 passing tests** for this slice only (`gemini-adapter.test.ts` — eleven named cases with T4 expanding to four error-class subcases; `second-provider-policy.test.ts` — two cases).

To run a subset by named case:

```bash
npx vitest run test/gemini-adapter.test.ts -t "request_mapping_golden"
```

## 6. Inspect the changes

Read the frozen contract:

```bash
cat specs/034-second-provider-adapter/contracts/second-provider-adapter.md
```

Open the adapter module and policy data:

```bash
less ai-platform/src/provider/gemini.ts
less ai-platform/control/routing-policy/platform-default/1.json
```

Run the focused test files:

```bash
cd ai-platform
npx vitest run test/gemini-adapter.test.ts test/second-provider-policy.test.ts
```
