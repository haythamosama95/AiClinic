import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { kCurrentWorker } from "miniflare";
import { pinWorkerdCompatibilityDate } from "./test/pin-workerd-compatibility-date";
import { defineConfig } from "vitest/config";

/**
 * Dedicated Cloudflare workers-pool config for the catalog E2E suite.
 * Do not run these files through `vitest.config.ts` (plain Node pool).
 */
export default defineConfig({
  plugins: [
    cloudflareTest({
      main: "./src/worker.ts",
      wrangler: {
        configPath: "./wrangler.toml",
        environment: "development",
      },
      miniflare: {
        // Keep in sync with workerd 1.20261012.1 in package-lock.json.
        compatibilityDate: pinWorkerdCompatibilityDate("2026-10-12"),
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
    }),
  ],
  test: {
    include: ["test/e2e/**/*.test.ts"],
    exclude: ["test/e2e/harness/**"],
    fileParallelism: false,
    testTimeout: 120_000,
    setupFiles: ["./test/e2e/setup.ts", "./test/setup-network.ts"],
    // Retry once for transient Workers runtime/storage cleanup failures. See
    // the longer comment in vitest.workers.config.ts for why retries are safe
    // with the campaign governor's stats.
    retry: 1,
  },
});
