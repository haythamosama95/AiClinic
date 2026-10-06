import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    include: ["test/system/**/*.system.test.ts"],
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
          d1Databases: ["DB"],
          r2Buckets: ["R2"],
          bindings: {
            TEST_CLOCK: "1",
            R2_LOCK_READ_TOKEN: "test-lock-read-token",
          },
        },
      },
    },
  },
});
