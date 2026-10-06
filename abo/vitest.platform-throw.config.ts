import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
import { pinWorkerdCompatibilityDate } from "../ai-platform/test/pin-workerd-compatibility-date";

const rootDir = path.dirname(fileURLToPath(import.meta.url));
const compatibilityDate = pinWorkerdCompatibilityDate();
const platformThrowStub = path.resolve(
  rootDir,
  "test/stubs/platform-throw/worker.ts",
);
const paymobStub = path.resolve(rootDir, "test/stubs/paymob/worker.ts");

export default defineWorkersConfig({
  test: {
    include: ["test/system/checkout-throw.cross-worker.test.ts"],
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
            PAYMOB_BASE_URL: "https://paymob.harness.test",
            PAYMOB_SECRET_KEY: "paymob-secret-test",
            PAYMOB_PUBLIC_KEY: "paymob-public-test",
            PAYMOB_CARD_INTEGRATION_ID: "123456",
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
              scriptPath: platformThrowStub,
            },
            {
              name: "paymob",
              compatibilityDate,
              modules: true,
              scriptPath: paymobStub,
            },
          ],
        },
      },
    },
  },
});
