# Phase 0 harness report

**Declaration: GREEN**

## 1. Files created

Harness:

- `ai-platform/test/e2e/harness/index.ts` (frozen barrel)
- `ai-platform/test/e2e/harness/env.ts`
- `ai-platform/test/e2e/harness/d1.ts`
- `ai-platform/test/e2e/harness/crypto.ts`
- `ai-platform/test/e2e/harness/aat.ts`
- `ai-platform/test/e2e/harness/control.ts`
- `ai-platform/test/e2e/harness/clinic.ts`
- `ai-platform/test/e2e/harness/gateway-object.ts`
- `ai-platform/test/e2e/harness/cron.ts`
- `ai-platform/test/e2e/harness/sse.ts`
- `ai-platform/test/e2e/harness/faults.ts`
- `ai-platform/test/e2e/harness/scenario.ts`
- `ai-platform/test/e2e/harness/types.ts`
- `ai-platform/test/e2e/harness/taxonomy.ts`

Suite:

- `ai-platform/test/e2e/setup.ts`
- `ai-platform/test/e2e/phase-00-exemplars.test.ts`
- `ai-platform/test/e2e/README.md`

Config (not production `src/`):

- `ai-platform/vitest.e2e.config.ts` (new)
- `ai-platform/vitest.config.ts` (exclude `test/e2e/**` from the Node pool)
- `ai-platform/package.json` (`test:e2e` script)

This report: `ai-platform/test/e2e/reports/phase-00-harness.md`

Production source (`ai-platform/src/`, `backend/supabase/migrations/`) was not modified.

## 2. Frozen API summary

Writers import only `./harness` (see `ai-platform/test/e2e/README.md`).

| Capability | API |
|---|---|
| D1 bootstrap | `bootstrapE2e()` applies real `ai-platform/migrations/*.sql`; `resetE2eState()` wipes business rows + R2 and reseeds `token_contract ver=1` |
| `[SEED]` | `seedSql` — documented as Journey-setup `[SEED]` only |
| AAT | `newScenario` → `enrollInstallation` (real `POST /control/.../enroll`) → `mintAat` with header `kid`/`alg` and payload `iss`/`aud`/`exp`/`iat`/`ver`/`scopes`/`role` |
| Control plane | `controlFetch(path, { auth })` — `operator` / `none` / `wrong` / `empty` / `basic` / `no-scheme` / `{ bearer }` |
| Clinic HTTP | `postRequest`, `getCapabilities`, `getRequestByRef`, `provisionHappyPath` |
| GatewayObject | `gatewayObjectRpc(installationId, body, { now })` — `idFromName` → `stub.fetch` |
| Cron | `invokeCron(cron)` → `worker.scheduled({ cron })` |
| SSE | `parseSseEvents`, `assertSseSequence` |
| Register 5 seams | `createRateLimiterDouble`, `wrapD1`, `wrapDurableObjectNamespace`, `wrapDoStorage`, `installEnvOverrides`, registry `setCapabilityRegistry`, `handleAdapterRequest`, quota `admissionRPC`/`creditRPC` |

## 3. Exemplar results

Command:

```bash
cd /home/haytham/Desktop/AiClinic/ai-platform && npx vitest run --config vitest.e2e.config.ts test/e2e/phase-00-exemplars.test.ts
```

Exact vitest summary (second run, `CONFIG_CACHE_TTL_MS=100`):

```
 Test Files  1 passed (1)
      Tests  3 passed (3)
   Start at  10:32:02
   Duration  3.51s
```

| Test | Result |
|---|---|
| `P00-001 — control-plane 401 unauthorized` | pass |
| `P00-002 — guard rejection full taxonomy body` | pass |
| `P00-003 — happy-path SSE accepted` | pass |

Pass: **3**. Fail: **0**. Skip: **0**.

## 4. Catalog-vs-code conflicts

1. **`CONFIG_CACHE_TTL_MS="0"` is unsafe for post-accept routing.** Catalog S00-011 / Register 5 #7 recommend TTL 0 so every consult misses. Code: `preloadRoutingPolicyForInstallation` `remember(now+ttl)` then `selectCandidateChain` only `consult`s. With TTL 0, `now >= expiresAt` in the same request → `ConfigCacheMissError` (`active_routing_policy`). Harness uses `"100"` plus `clearConfigCache()` after control mutations. Follow code.

2. **AAT claim is `role`, not `roles`.** Catalog prompt said “roles”; `identity/index.ts` payload field is `role`.

3. **`worker.fetch` ignores `_bindings`.** Catalog Register 5 often says pass wrappers via the `bindings` parameter. `fetch(request, _bindings, ctx)` reads `env` from `cloudflare:workers`. Cron `scheduled(controller, runtimeEnv)` **does** take injected env. `installEnvOverrides` tries to mutate pool `env` for `SELF.fetch`; if that throws, use `dispatchControl` / `invokeCron` / `gatewayObjectRpc({ namespace })`.

4. **Kill-switch control routes exist.** Register 5 #27: “No control-plane endpoint writes `kill_switch`.” Code exports `handleKillSwitchArm` / `handleKillSwitchDisarm` (`POST /control/kill-switches/{arm,disarm}`). Harness exposes `controlHandlers.handleKillSwitchArm` / `handleKillSwitchDisarm`. Follow code.

5. **Default entitle window.** Catalog Stage 4 examples use `period_end: 2026-09-01`. Wall clock is 2026-09-05. Harness default is `2026-01-01` … `2027-01-01`.

6. **Control-plane 401 is not taxonomy.** Confirmed against code: `{ "error": "unauthorized" }` (`control/http.ts`). Exemplar P00-001 asserts that.

No conflict required weakening an exemplar assertion.

## 5. How later stages should invoke vitest

```bash
cd /home/haytham/Desktop/AiClinic/ai-platform
npx vitest run --config vitest.e2e.config.ts test/e2e/stage-NN-*
# or
npm run test:e2e -- test/e2e/stage-NN-*
```

Full E2E suite: `npx vitest run --config vitest.e2e.config.ts`.

Do **not** run `test/e2e/**` through default `vitest.config.ts` (Node pool; `cloudflare:test` is unavailable).

## 6. Declaration

**GREEN**
