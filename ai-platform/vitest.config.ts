import { defineConfig } from "vitest/config";

export default defineConfig({
  test: {
    include: ["test/**/*.test.ts"],
    exclude: [
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
    ],
    testTimeout: 120_000,
    fileParallelism: false,
  },
});
