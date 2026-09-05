import { readFileSync } from "node:fs";
import { defineConfig, type Plugin } from "vitest/config";

function promptArtifactPlugin(): Plugin {
  return {
    name: "prompt-artifact-text",
    enforce: "pre",
    load(id) {
      if (!id.endsWith(".md") || id.includes("\0")) {
        return null;
      }
      const source = readFileSync(id, "utf8");
      return `export default ${JSON.stringify(source)}`;
    },
  };
}

export default defineConfig({
  plugins: [promptArtifactPlugin()],
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
      "test/support-purge.test.ts",
      "test/pipeline.test.ts",
      "test/retention.test.ts",
      "test/rollup-reconciliation.test.ts",
      "test/journal-dashboards.test.ts",
      "test/soft-threshold-routing.test.ts",
      "test/conversational-journaling.test.ts",
      "test/capability-deprecation.test.ts",
      "test/cohort-activate-promote.test.ts",
      "test/routing-policy-canary.test.ts",
      "test/token-contract-control.test.ts",
      "test/discovery-http.test.ts",
      "test/config-readers.test.ts",
      "test/load/**",
      "test/worker-request-orchestrator.test.ts",
      "test/entitle-grant.test.ts",
      "test/quota-inspect.test.ts",
      "test/system/**/*.system.test.ts",
      "test/e2e/**",
    ],
    testTimeout: 120_000,
    fileParallelism: false,
  },
});
