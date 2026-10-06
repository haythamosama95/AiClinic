import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
import { kCurrentWorker } from "miniflare";
import { pinWorkerdCompatibilityDate } from "./test/pin-workerd-compatibility-date";

/**
 * Dedicated Cloudflare workers-pool config for the catalog E2E suite.
 * Do not run these files through `vitest.config.ts` (plain Node pool).
 */
export default defineWorkersConfig({
  test: {
    include: ["test/e2e/**/*.test.ts"],
    exclude: ["test/e2e/harness/**"],
    fileParallelism: false,
    testTimeout: 120_000,
    setupFiles: ["./test/e2e/setup.ts"],
    poolOptions: {
      workers: {
        main: "./src/worker.ts",
        wrangler: {
          configPath: "./wrangler.toml",
          environment: "development",
        },
        miniflare: {
          // wrangler.toml keeps 2026-05-03 for production Cloudflare.
          // Pin local workerd to the date it actually runs so the
          // 2026-05-03 → 2025-09-06 fallback cannot stay silent.
          compatibilityDate: pinWorkerdCompatibilityDate(),
          d1Databases: ["DB"],
          r2Buckets: ["R2"],
          ratelimits: {
            RATE_LIMITER_INSTALLATION: {
              simple: { limit: 600, period: 60 },
            },
            RATE_LIMITER_INSTALLATION_ACTOR: {
              simple: { limit: 120, period: 60 },
            },
            RATE_LIMITER_INSTALLATION_CAPABILITY: {
              simple: { limit: 300, period: 60 },
            },
          },
          bindings: {
            DURATION_SCALE: "staging",
            // TTL 0: no cross-request caching. Same-request preload still
            // serves consult (`now > expiresAt`) and the worker passes the
            // preloaded policy row through so routing never re-consults.
            CONFIG_CACHE_TTL_MS: "0",
            ISSUER_ID: "issuer-test",
            PLATFORM_SIGNING_KEY:
              '{"kid":"platform-test","pkcs8":"MC4CAQAwBQYDK2VwBCIEIN2ndQQArm1dlsCuHaGGaUB8nnqfj7W2HaVbj_JJA9Lk","public_key":"GNzxZ6Gymues_aeJArGyb3wDESTOUJeqhuZBfTByni0"}',
            ACCESS_TEAM_DOMAIN: "access.test",
            ACCESS_AUD: "vendor-access-aud",
            WEBAUTHN_RP_ID: "ops.vendor.test",
            WEBAUTHN_ORIGIN: "https://ops.vendor.test",
            ALERT_EMAIL_TO: "alerts@clinic.invalid",
          },
          serviceBindings: {
            VENDOR: { name: kCurrentWorker, entrypoint: "VendorEntrypoint" },
          },
        },
      },
    },
  },
});
