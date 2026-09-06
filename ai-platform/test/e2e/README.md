# AI Platform E2E harness — frozen API

Stage writers import **only** from `ai-platform/test/e2e/harness` (the barrel).
Do not modify this directory after Phase 0. If a scenario needs a missing
helper, leave a `// HARNESS-GAP:` comment in the test.

## 1. How to run

From `ai-platform/`:

```bash
npx vitest run --config vitest.e2e.config.ts test/e2e/phase-00-exemplars.test.ts
npx vitest run --config vitest.e2e.config.ts test/e2e/stage-NN-*
npx vitest run --config vitest.e2e.config.ts
```

Equivalent npm script: `npm run test:e2e -- test/e2e/stage-NN-*`.

This suite uses `@cloudflare/vitest-pool-workers` against `src/worker.ts` and
`wrangler.toml` `[env.development]`. It is excluded from the plain Node
`vitest.config.ts` pool. Do not run E2E files with `npx vitest run` (no
`--config`).

Test env overrides (miniflare bindings):

| Binding | Value |
|---|---|
| `OPERATOR_BEARER_TOKEN` | `test-operator-bearer-token` (`OPERATOR_BEARER`) |
| `OPERATOR_ID` | `platform-operator` (matches wrangler development vars / catalog) |
| `CONFIG_CACHE_TTL_MS` | `"100"` (see §6 — do not use `"0"`) |

## 2. Per-file boilerplate

```ts
import { beforeAll, beforeEach } from "vitest";
import { bootstrapE2e, resetE2eState } from "./harness";

beforeAll(async () => {
  await bootstrapE2e();
});

beforeEach(async () => {
  await resetE2eState();
});
```

`bootstrapE2e()` applies the **real** files in `ai-platform/migrations/` to the
pool D1 (not a fake schema). `resetE2eState()` deletes business rows, clears
R2, re-inserts the migration `token_contract` seed (`ver='1'`), and clears
the isolate config cache.

## 3. `[SEED]` discipline

`seedSql(statements)` writes D1 directly. Call it **only** when the scenario
Journey setup says `[SEED]`. Every other prior state must be built with the
real operations below (`enrollInstallation`, `entitleInstallation`,
`publishPolicy`, `promotePolicy`, `provisionHappyPath`, `mintAat`,
`postRequest`, `invokeCron`, `gatewayObjectRpc`, …).

## 4. Frozen API

### 4.1 Constants and pool handles

`SELF`, `env`, `GATEWAY_ORIGIN`, `OPERATOR_BEARER`, `OPERATOR_ID`,
`WRONG_OPERATOR_BEARER`, `CAPABILITY_ID`, `CAPABILITY_VERSION`, `POLICY_ID`,
`POLICY_VERSION`, `POLICY_REF`, `AAT_AUDIENCE`, `TOKEN_CONTRACT_VER`,
`QUOTA_DO_RPC_URL`, `PLATFORM_TABLES`, `TAXONOMY_BODY_KEYS`,
`REQUEST_REFERENCE_PATTERN`, `ULID_PATTERN`, `CRON_RETENTION` (`0 3 * * *`),
`CRON_ROLLUP` (`0 4 * * *`).

### 4.2 D1 / R2

- `applyAllMigrations(db?)` / `applySql(db, sql)` — real migration SQL
- `bootstrapE2e()` / `resetE2eState()` / `resetPlatformState()`
- `clearConfigCache()`
- `seedSql([{ sql, params? }])` — **`[SEED]` only**
- `queryOne` / `queryAll` / `count` / `d1.*`
- `getAiRequest` / `getAttempts` / `getUsageEvents` / `getEntitlement` /
  `getGrants` / `getAudits` / `getRoutingPolicy`
- `getR2Json` / `r2Exists` / `listTableNames`

### 4.3 AAT minting (real enroll path)

1. `const scenario = await newScenario()` — fresh UUIDs + Ed25519 keypair.
2. `await enrollInstallation(scenario)` — `POST /control/installations/{id}/enroll`
   with operator bearer (not a D1 bypass).
3. `await mintAat(scenario, options?)` — compact EdDSA JWS.

`mintAat` claim/header control (`MintAatOptions`):

| Field | What it controls |
|---|---|
| `kid` / `alg` / `header` | JWT header (`kid` defaults to the enrolled key) |
| `claims` | Payload overrides: `iss`, `aud`, `sub`, `org`, `branch`, `role`, `scopes`, `jti`, `iat`, `exp`, `ver`, plus extras |
| `omitClaims` / `omitHeaderFields` | Drop keys after defaults |
| `keypair` | Sign with a different key |
| `signatureB64` | Replace the signature segment |
| `skipValidityWait` | Do not wait for `installation_key.valid_from` |

The live claim name is **`role`** (singular), not `roles`. Default
`aud = "ai-platform"`, `ver = "1"`, `exp − iat = 330` (under the 600 s cap).
`mintAat` waits until `valid_from` is visible to the verifier clock
(`floor(now/1000)*1000`) unless `skipValidityWait` is set.

Low-level: `generateTestKeypair()`, `signJwt({ header, payload, privateKey })`.

### 4.4 Control plane

`controlFetch(path, { method, body, auth, headers, clinicToken })`.

`auth` variants: `"operator"` (default), `"none"`, `"wrong"`, `"empty"`,
`"basic"`, `"no-scheme"`, `{ bearer }`, `{ authorization }`. Pass a clinic AAT
as `{ bearer: aat }` or `clinicToken`.

Helpers (all real HTTP via `SELF.fetch`): `enrollInstallation`,
`entitleInstallation`, `publishPolicy`, `canaryPolicy`, `promotePolicy`,
`rollbackPolicy`, `enrollPayload`, `fakePolicyDocument`, `fakePolicyTarget`,
`DEFAULT_ENTITLE_PAYLOAD` (period 2026-01-01 … 2027-01-01, covers wall clock).

Direct dispatch with injected bindings (Register 5 missing-binding /
`storage_error` / `invalid_route`):

- `dispatchControl(request, bindings?, auth?)`
- `controlHandlers.*` (lifecycle, entitle, routing, token-contract, purge,
  quota inspect, kill-switch, …)
- `operatorAuthFromEnv()` / `controlBindingsFromEnv(overrides)`

### 4.5 Clinic-facing HTTP

- `clinicFetch(path, { method, token, headers, body, signal })`
- `postRequest(scenario, opts)` — `POST /v1/requests`. `token: null` omits
  `Authorization`. Returns `{ status, headers, body, events, text }`
  (`events` filled when `content-type` is SSE).
- `getCapabilities(token, ifNoneMatch?)`
- `getRequestByRef(token, ref)`
- `getHealth()`
- `visitSummaryInvokeBody(scenario, overrides?)`

`provisionHappyPath(scenario?)` — enroll + entitle + publish + promote fake
provider policy. Throws if any step is not HTTP 200.

### 4.6 GatewayObject RPC

`gatewayObjectRpc(installationId, body, { now, method, namespace, rawBody })`
does `env.DO.idFromName(installationId)` → `stub.fetch(QUOTA_DO_RPC_URL)`.
Pass `now` to inject the DO clock. `gatewayObjectJson` parses the body.

There is no public HTTP route to the DO (`S00-015`).

### 4.7 Cron

`invokeCron(cron, runtimeEnv?, scheduledTime?)` calls
`worker.scheduled({ cron })` with the pool env (or a wrapped env).
Use `CRON_RETENTION` / `CRON_ROLLUP`.

### 4.8 SSE

- `parseSseEvents(response)` / `parseSseText(text)` → `{ event, data }[]`
- `assertSseSequence(events, expectedNames, mode?)` — `prefix` (default),
  `exact`, or `subsequence`
- `sseEventNames` / `terminalEventTypes`

Happy-path first event is `accepted` with `request_reference` and `trace_id`.

### 4.9 Taxonomy bodies

`assertTaxonomyBody(json, { code, retry_safe? })` checks
`code`, `request_reference`, `trace_id`, `retry_safe` (Register 1A /
`buildErrorBody`). Supplementary keys (`retry_after`, …) are allowed.
Control-plane errors are **not** taxonomy: `{ "error": "<string>" }`
(401 is exactly `{ "error": "unauthorized" }`).

`assertRequestReferenceShape` / `assertUlidShape`.

### 4.10 Register 5 seams (faults / doubles)

| Helper | Seam |
|---|---|
| `createRateLimiterDouble({ success, retryAfter? })` | CF rate-limiter double (#31). Omit `retryAfter` for the fallback-to-60 path |
| `wrapD1(db, { batchThrow, batchUniqueThrow, prepareThrow, runThrow, execThrow })` | Fault-injecting D1 (#19, #28, #29) |
| `wrapDurableObjectNamespace(ns, { fetchThrow, scriptedFetch })` | DO unavailable / scripted 4xx/5xx (#28) |
| `wrapDoStorage(storage, { getThrow, putThrow, deleteThrow })` | Storage fault for `admissionRPC`/`creditRPC` (#45) |
| `installEnvOverrides({ DB, DO, RATE_LIMITER_* })` | Try to swap pool `env` for a following `SELF.fetch`; **restore in `afterEach`** |
| `diskIoError()` / `uniqueConstraintError(target)` | Standard throw payloads |
| `setCapabilityRegistry` / `createCapabilityRegistry` / `loadManifest` | Registry seam (#3, #30) |
| `handleAdapterRequest` | Adapter-contract scenarios unreachable via production wiring (#39) |
| `admissionRPC` / `creditRPC` / `releaseRPC` / `inspectRPC` | Quota logic with injected storage |

`worker.fetch` ignores its `_bindings` argument and reads `env` from
`cloudflare:workers`. If `installEnvOverrides` throws (frozen binding), pass
wrappers into `dispatchControl` / `invokeCron` / `gatewayObjectRpc({ namespace })`
instead of `SELF.fetch`.

## 5. What writers must NOT do

- Import production modules to bypass the harness, except through this barrel.
- Seed D1 unless the scenario says `[SEED]`.
- Invent a fake schema, fake enroll, or unsigned “test token” helper.
- Hit GatewayObject through a made-up public URL — use `gatewayObjectRpc`.
- Fire cron through `/__scheduled` or `/cdn-cgi/handler/scheduled` — use
  `invokeCron`.
- Modify `ai-platform/src/` or `backend/supabase/migrations/`.
- Weaken assertions when catalog and code disagree — follow **code** and
  record the conflict.
- Name files `stage-NN-*.test.ts` from this Phase 0 tree (exemplars are
  `phase-00-exemplars.test.ts`).

## 6. Catalog-vs-code notes baked into this API

- Control 401 body is `{ "error": "unauthorized" }` (not the clinic taxonomy).
- AAT staff claim is `role`, not `roles`.
- `worker.fetch` does not honor the `bindings` parameter; cron **does** take
  `runtimeEnv`.
- Code has `POST /control/kill-switches/{arm,disarm}` (`control/kill-switch.ts`).
  Register 5 #27 still says no kill-switch control route — follow code;
  `controlHandlers.handleKillSwitchArm` / `handleKillSwitchDisarm` exist.
- Default entitle window in this harness is 2026-01-01 … 2027-01-01 so
  wall-clock “now” (2026-09) is inside the period. Catalog examples that use
  2026-07-01 … 2026-09-01 are past `period_end` as of 2026-09-05.
- Catalog S00-011 / Register 5 #7 recommend `CONFIG_CACHE_TTL_MS="0"` so
  cross-request consults miss. The pool uses `"0"`: same-request preload still
  serves (`consult` uses `now > expiresAt`; the worker passes the preloaded
  policy row into `selectCandidateChain`). `clearConfigCache()` after control
  mutations remains available (already called by enroll / entitle / publish /
  promote helpers).
