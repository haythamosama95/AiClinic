import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
import { pinWorkerdCompatibilityDate } from "../ai-platform/test/pin-workerd-compatibility-date";

const rootDir = path.dirname(fileURLToPath(import.meta.url));
// Keep in sync with Miniflare 4.20250906.0 in this package's lockfile.
const compatibilityDate = pinWorkerdCompatibilityDate("2025-09-06");
const paymobStub = path.resolve(rootDir, "test/stubs/paymob/worker.ts");
const paymobModulesRoot = path.dirname(paymobStub);
const platformStub = path.resolve(
  rootDir,
  "test/stubs/platform-throw/worker.ts",
);
const platformModulesRoot = path.dirname(platformStub);

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
          compatibilityDate,
          d1Databases: ["DB"],
          r2Buckets: ["R2"],
          bindings: {
            TEST_CLOCK: "1",
            R2_LOCK_READ_TOKEN: "test-lock-read-token",
            PAYMOB_BASE_URL: "https://paymob.harness.test",
            PAYMOB_HMAC_SECRET: "paymob-hmac-test-secret",
            PAYMOB_API_KEY: "paymob-api-test-key",
            // R9-CRON1 / RT2: distinct per-stream URLs so tests can tell the streams apart.
            HEARTBEAT_URL_MINUTE: "https://heartbeat.test/minute",
            HEARTBEAT_URL_DIGEST: "https://heartbeat.test/digest",
          },
          serviceBindings: {
            PLATFORM: { name: "platform", entrypoint: "VendorEntrypoint" },
            PAYMOB_STUB: "paymob",
          },
          workers: [
            {
              name: "platform",
              compatibilityDate,
              modules: true,
              scriptPath: platformStub,
              modulesRoot: platformModulesRoot,
              modulesRules: [
                { type: "ESModule", include: ["**/*.ts", "**/*.mts"] },
              ],
            },
            {
              name: "paymob",
              compatibilityDate,
              modules: true,
              scriptPath: paymobStub,
              modulesRoot: paymobModulesRoot,
              modulesRules: [
                { type: "ESModule", include: ["**/*.ts", "**/*.mts"] },
              ],
            },
          ],
        },
      },
    },
  },
});
