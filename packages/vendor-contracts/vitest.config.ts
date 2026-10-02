import path from "node:path";
import { defineConfig } from "vitest/config";

export default defineConfig({
  resolve: {
    alias: {
      "vendor-contracts": path.resolve(import.meta.dirname, "src/index.ts"),
    },
  },
  test: {
    include: ["test/**/*.test.ts"],
    fileParallelism: false,
  },
});
