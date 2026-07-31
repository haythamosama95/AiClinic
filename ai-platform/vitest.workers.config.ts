import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    include: ["test/control.test.ts"],
    fileParallelism: false,
    testTimeout: 120_000,
    poolOptions: {
      workers: {
        miniflare: {
          compatibilityDate: "2026-05-03",
          d1Databases: ["DB"],
        },
      },
    },
  },
});
