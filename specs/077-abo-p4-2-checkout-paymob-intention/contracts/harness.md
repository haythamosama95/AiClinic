# H-PAY and H-XW (frozen)

## 1. H-PAY

Auxiliary Miniflare worker `abo/test/stubs/paymob/worker.ts`, named `paymob` in the cross-worker vitest config.

| Route | Behaviour |
| --- | --- |
| `POST /v1/intention/` | Default mode `ok`: HTTP 200 `{id, intention_order_id, client_secret}` and store the JSON body. Mode `refuse`: HTTP 500. Mode `timeout`: do not respond, so the adapter abort fires |
| `POST /api/auth/tokens` | HTTP 200 `{token: "stub-token"}` |
| `POST /__script` | Body `{mode: "ok" \| "refuse" \| "timeout"}`. Test-only |
| `GET /__last` | Last intention JSON body. Test-only |

The adapter does not call `/__script` or `/__last`. It `fetch`es `PAYMOB_BASE_URL`. The cross-worker harness `fetchMock`s that origin and forwards the request to the `paymob` service binding, including the abort signal. The test scripts the stub with `env.PAYMOB_STUB.fetch("/__script")` and reads the capture with `GET /__last`. `PAYMOB_STUB` exists only in the vitest Miniflare config.

## 2. H-XW

`abo/scripts/build-platform-for-hxw.mjs` bundles `ai-platform` with wrangler into `ai-platform/dist/hxw/worker.js` (`dist/` is gitignored).

`abo/vitest.cross-worker.config.ts` runs main `abo/src/worker.ts` and Miniflare auxiliary workers:

- `platform`: that bundle, `entrypoint = "VendorEntrypoint"`, its own D1 bound as `DB` and also exposed to the test as `PLATFORM_DB`, plus R2 and durable object `GatewayObject` under binding `DO`, and the `[env.development]` vars from `ai-platform/wrangler.toml`. The harness applies `ai-platform/migrations/*.sql` to `PLATFORM_DB` in filename order before a scenario calls the platform.
- `paymob`: the H-PAY worker.

ABO `PLATFORM` is a service binding to `platform` / `VendorEntrypoint`. Production, staging, and development `abo/wrangler.toml` declare the same binding to the matching `ai-platform-gateway-*` worker name. They do not declare `PAYMOB_STUB` or `PLATFORM_DB`. They do not set `TEST_CLOCK`.

E2E-P4.2-03 uses `abo/vitest.platform-throw.config.ts`. `PLATFORM` is `abo/test/stubs/platform-throw/worker.ts` exporting class `VendorEntrypoint`. `getCoverage` returns the result envelope `{result: "transient", code: "transient", detail: "unavailable", contract_version: 1}` when `org_id` ends with `aa`; otherwise it throws. H-PAY is still bound. The test inserts the `coverage_view` row before `POST /v1/checkouts`.

Active coverage for E2E-P4.2-02 and E2E-P4.2-08 is created by calling the bound `publishPlanVersion`, `registerServiceKey`, and paid `grant` through `vendor-contracts` testkit signing, until `getCoverage` returns snapshot `state` `active`.

## 3. Import boundary

`abo/scripts/check-import-boundary.mjs <src-root>` exits 0 when both hold, and 1 otherwise:

- The only file that imports a module under `provider/paymob/` other than `adapter.ts` is `provider/paymob/adapter.ts`.
- No file outside `provider/` imports `provider/paymob/adapter.ts`.

Relative `from` and `import()` specifiers are resolved against the importing file. The CI job runs the script on `abo/src` (must exit 0) and E2E-P4.2-09 runs it on `abo/test/fixtures/import-boundary/bad/src` (must exit 1). That fixture is a domain module that imports the adapter. The fixture is not part of the worker bundle.
