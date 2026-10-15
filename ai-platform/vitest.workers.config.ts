import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
import { kCurrentWorker } from "miniflare";
import { pinWorkerdCompatibilityDate } from "./test/pin-workerd-compatibility-date";

export default defineWorkersConfig({
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
    setupFiles: ["./test/setup-isolate-config-cache.ts"],
    // Retry once to absorb residual @cloudflare/vitest-pool-workers isolated
    // storage flakiness: the pool snapshots/rolls back D1/R2/DO storage around
    // every test, and if the per-test storage stack fails to pop cleanly
    // (e.g. an uncaught rejection racing the pop), the runner aborts with
    // "Isolated storage failed. There should be additional logs above." and
    // fails effectively random downstream tests. The SEND_EMAIL stub
    // (test/stub-send-email-binding.ts) and the pool upgrade to 0.12.21
    // (workers-sdk fixes #11031 / #11690) address the root causes; this retry
    // is the last-resort net. Safe with the campaign governor: it dedupes
    // recorded test statuses by name keeping the latest attempt
    // (test/harness/test_result_stats.py `dedupe_test_statuses`), so a
    // retried-then-passing test is not counted as a distinct failure.
    retry: 1,
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
      },
    },
  },
});
