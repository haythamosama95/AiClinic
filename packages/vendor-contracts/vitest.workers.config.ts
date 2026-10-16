import path from "node:path";
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

const packageRoot = import.meta.dirname;

export default defineWorkersConfig({
  resolve: {
    alias: [
      {
        find: /^vendor-contracts\/testkit$/,
        replacement: path.resolve(packageRoot, "src/testkit/index.ts"),
      },
      {
        find: /^vendor-contracts$/,
        replacement: path.resolve(packageRoot, "src/index.ts"),
      },
    ],
  },
  test: {
    include: ["test/**/*.test.ts"],
    exclude: ["test/bundle-scan.test.ts"],
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
