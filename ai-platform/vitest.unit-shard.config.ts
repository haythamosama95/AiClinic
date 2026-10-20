import { mergeConfig, defineConfig } from "vitest/config";
import config from "./vitest.config";

export default mergeConfig(
  config,
  defineConfig({
    test: {
      exclude: ["test/migrations.test.ts"],
    },
  }),
);
