import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
import { pinWorkerdCompatibilityDate } from "../ai-platform/test/pin-workerd-compatibility-date";

const rootDir = path.dirname(fileURLToPath(import.meta.url));
const compatibilityDate = pinWorkerdCompatibilityDate();
const platformBundleDir = path.resolve(rootDir, ".hxw-platform");
const platformBundle = path.join(platformBundleDir, "worker.js");
const paymobStub = path.resolve(rootDir, "test/stubs/paymob/worker.ts");
const paymobModulesRoot = path.dirname(paymobStub);

const PLATFORM_DB_ID = "22222222-2222-2222-2222-222222222222";

const platformWorkerBindings = {
  BUILD_SHA: "local",
  ENVIRONMENT: "development",
  LOG_VERBOSITY: "2",
  CONFIG_CACHE_TTL_MS: "100",
  DURATION_SCALE: "staging",
  ACCESS_TEAM_DOMAIN: "access.test",
  ACCESS_AUD: "vendor-access-aud",
  WEBAUTHN_RP_ID: "ops.vendor.test",
  WEBAUTHN_ORIGIN: "https://ops.vendor.test",
  HEARTBEAT_URL: "https://heartbeat.test/ping",
  ALERT_EMAIL_TO: "alerts@clinic.invalid",
  ISSUER_ID: "issuer-test",
  PLATFORM_SIGNING_KEY:
    '{"kid":"platform-test","pkcs8":"MC4CAQAwBQYDK2VwBCIEIN2ndQQArm1dlsCuHaGGaUB8nnqfj7W2HaVbj_JJA9Lk","public_key":"GNzxZ6Gymues_aeJArGyb3wDESTOUJeqhuZBfTByni0"}',
};

export default defineWorkersConfig({
  test: {
    include: [
      "test/system/checkout.cross-worker.test.ts",
      "test/system/coverage-view.cross-worker.test.ts",
    ],
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
          d1Databases: {
            DB: "11111111-1111-1111-1111-111111111111",
            PLATFORM_DB: PLATFORM_DB_ID,
          },
          r2Buckets: ["R2"],
          bindings: {
            TEST_CLOCK: "1",
            PAYMOB_BASE_URL: "https://paymob.harness.test",
            PAYMOB_SECRET_KEY: "paymob-secret-test",
            PAYMOB_PUBLIC_KEY: "paymob-public-test",
            PAYMOB_CARD_INTEGRATION_ID: "123456",
            ACCESS_TEAM_DOMAIN: "access.test",
            ACCESS_AUD: "vendor-access-aud",
            WEBAUTHN_RP_ID: "ops.vendor.test",
            WEBAUTHN_ORIGIN: "https://ops.vendor.test",
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
              scriptPath: platformBundle,
              modulesRoot: platformBundleDir,
              modulesRules: [
                {
                  type: "Text",
                  include: ["**/*.md"],
                  fallthrough: true,
                },
              ],
              d1Databases: {
                DB: PLATFORM_DB_ID,
              },
              r2Buckets: ["R2"],
              durableObjects: {
                DO: { className: "GatewayObject", useSQLite: true },
              },
              bindings: platformWorkerBindings,
              ratelimits: {
                RATE_LIMITER_INSTALLATION: {
                  simple: { limit: 600, period: 60 },
                },
                RATE_LIMITER_INSTALLATION_ACTOR: {
                  simple: { limit: 120, period: 60 },
                },
                RATE_LIMITER_INSTALLATION_CAPABILITY: {
                  simple: { limit: 300, period: 60 },
                },
              },
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
