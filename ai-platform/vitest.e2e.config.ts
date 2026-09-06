import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

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
          compatibilityDate: "2026-05-03",
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
            OPERATOR_BEARER_TOKEN: "test-operator-bearer-token",
            OPERATOR_ID: "platform-operator",
            // TTL 0: no cross-request caching. Same-request preload still
            // serves consult (`now > expiresAt`) and the worker passes the
            // preloaded policy row through so routing never re-consults.
            CONFIG_CACHE_TTL_MS: "0",
          },
        },
      },
    },
  },
});
