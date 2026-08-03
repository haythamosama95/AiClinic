import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    include: [
      "test/control.test.ts",
      "test/identity.test.ts",
      "test/entitlement.test.ts",
      "test/rate-limit.test.ts",
      "test/quota-do.test.ts",
      "test/admission-credit.test.ts",
      "test/capability.test.ts",
      "test/journal.test.ts",
      "test/support-lookup.test.ts",
      "test/retention.test.ts",
      "test/rollup-reconciliation.test.ts",
      "test/journal-dashboards.test.ts",
      "test/soft-threshold-routing.test.ts",
      "test/conversational-journaling.test.ts",
      "test/capability-deprecation.test.ts",
      "test/cohort-activate-promote.test.ts",
      "test/routing-policy-canary.test.ts",
      "test/token-contract-control.test.ts",
      "test/load/load-and-cost.test.ts",
    ],
    fileParallelism: false,
    testTimeout: 120_000,
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
        },
      },
    },
  },
});
