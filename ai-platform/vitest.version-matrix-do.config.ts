import path from "node:path";
import { fileURLToPath } from "node:url";
import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";
import { kCurrentWorker } from "miniflare";
import { unstable_getMiniflareWorkerOptions } from "wrangler";
import { pinWorkerdCompatibilityDate } from "./test/pin-workerd-compatibility-date";

const rootDir = path.dirname(fileURLToPath(import.meta.url));
const compatibilityDate = pinWorkerdCompatibilityDate();
const variantDir = path.resolve(rootDir, "../e2e/fullstack/test/variant");
const platformWorkerNConfig = path.join(variantDir, "platform-worker-n.toml");
const platformDoReceiverConfig = path.join(variantDir, "platform-do-receiver.toml");

const doReceiverWorker = unstable_getMiniflareWorkerOptions(
  platformDoReceiverConfig,
  "development",
);

export default defineWorkersConfig({
  test: {
    include: ["test/version-matrix/worker-do.system.test.ts"],
    fileParallelism: false,
    testTimeout: 120_000,
    setupFiles: ["./test/setup-isolate-config-cache.ts"],
    poolOptions: {
      workers: {
        main: "./src/worker.ts",
        wrangler: {
          configPath: platformWorkerNConfig,
          environment: "development",
        },
        miniflare: {
          compatibilityDate,
          d1Databases: ["DB"],
          r2Buckets: ["R2"],
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
          bindings: {
            TEST_CLOCK: "1",
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
          },
          serviceBindings: {
            VENDOR: { name: kCurrentWorker, entrypoint: "VendorEntrypoint" },
          },
          workers: [doReceiverWorker],
        },
      },
    },
  },
});
