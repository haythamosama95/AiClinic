import path from "node:path";
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  resolve: {
    alias: {
      "vendor-contracts": path.resolve(import.meta.dirname, "src/index.ts"),
    },
  },
  test: {
    include: ["test/**/*.test.ts"],
    fileParallelism: false,
    poolOptions: {
      workers: {
        wrangler: {
          configPath: "./wrangler.toml",
        },
      },
    },
  },
});
