import { cloudflareTest } from "@cloudflare/vitest-plugin";
import { kCurrentWorker } from "miniflare";
import { pinWorkerdCompatibilityDate } from "./test/pin-workerd-compatibility-date";
import { defineConfig } from "vitest/config";

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
          TEST_CLOCK: "1",
          DURATION_SCALE: "staging",
          ACCESS_TEAM_DOMAIN: "access.test",
          ACCESS_AUD: "vendor-access-aud",
          WEBAUTHN_RP_ID: "ops.vendor.test",
          WEBAUTHN_ORIGIN: "https://ops.vendor.test",
          HEARTBEAT_URL: "https://heartbeat.test/ping",
          ALERT_EMAIL_TO: "alerts@clinic.invalid",
          ISSUER_ID: "issuer-test",
          PLATFORM_SIGNING_KEY:
            '{"kid":"platform-test","pkcs8":"MC4CAQAwBQYDK2VwBCIEIN2ndQQArm1dlsCuHaGGaUB8nnqfj7W2HaVbj_JJA9Lk","public_key":"GNzxZ6Gymues_aeJArGyb3wDESTOUJeqhuZBfTByni0"}',
        },
        serviceBindings: {
          VENDOR: { name: kCurrentWorker, entrypoint: "VendorEntrypoint" },
        },
      },
    }),
  ],
  test: {
    include: [
      "test/vendor-entrypoint.test.ts",
      "test/identity.test.ts",
      "test/entitlement.test.ts",
      "test/rate-limit.test.ts",
      "test/quota-do.test.ts",
      "test/admission-credit.test.ts",
      "test/capability.test.ts",
      "test/journal.test.ts",
      "test/support-lookup.test.ts",
      "test/support-purge.test.ts",
      "test/retention.test.ts",
      "test/rollup-reconciliation.test.ts",
      "test/journal-dashboards.test.ts",
      "test/soft-threshold-routing.test.ts",
      "test/conversational-journaling.test.ts",
      "test/pipeline.test.ts",
      "test/capability-deprecation.test.ts",
      "test/cohort-activate-promote.test.ts",
      "test/routing-policy-canary.test.ts",
      "test/token-contract-control.test.ts",
      "test/discovery-http.test.ts",
      "test/config-readers.test.ts",
      "test/load/load-and-cost.test.ts",
      "test/worker-request-orchestrator.test.ts",
      "test/plan-catalogue.test.ts",
      "test/quota-inspect.test.ts",
      "test/usage-summary.test.ts",
      "test/system/**/*.system.test.ts",
    ],
    fileParallelism: false,
    testTimeout: 120_000,
    setupFiles: ["./test/setup-isolate-config-cache.ts", "./test/setup-network.ts"],
    // Retry once for transient Workers runtime/storage cleanup failures. The
    // SEND_EMAIL stub (test/stub-send-email-binding.ts) addresses the known
    // cleanup trigger. Safe with the campaign governor: it dedupes
    // recorded test statuses by name keeping the latest attempt
    // (test/harness/test_result_stats.py `dedupe_test_statuses`), so a
    // retried-then-passing test is not counted as a distinct failure.
    retry: 1,
  },
});
