import path from "node:path";
import { defineConfig } from "vitest/config";

const packageRoot = import.meta.dirname;

export default defineConfig({
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
    fileParallelism: false,
  },
});
